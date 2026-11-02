defmodule PauseAiCa.OutreachAttachments do
  @moduledoc "Private persistent blobs; provider capabilities never become browser URLs."
  alias PauseAiCa.Repo
  alias PhoenixMailWorkflow.Inbound.Brevo
  import Ecto.Query
  @max_bytes 10_485_760

  def ensure(receipt) do
    rules =
      Enum.map(PauseAiCa.Outreach.Mailboxes.configured(), fn box ->
        %{id: box.id, receiving_addresses: box.receiving_addresses, root_addresses: [box.email]}
      end)

    case Brevo.normalize(receipt.payload, rules) do
      {:ok, %{messages: messages}} ->
        Enum.reduce_while(messages, :ok, fn message, :ok ->
          case fetch_message(receipt.id, message) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      _ ->
        :ok
    end
  end

  def decorate(message) do
    source = message.source || %{}
    receipt_id = source["receipt_id"]
    item_index = source["item_index"]

    attachments =
      Enum.map(message.attachments || [], fn descriptor ->
        index = value(descriptor, :attachment_index) || value(descriptor, :index)

        if valid_locator?(receipt_id, item_index, index) and
             File.regular?(blob_path(receipt_id, item_index, index)) do
          Map.put(
            descriptor,
            "download_path",
            "/manage/mail/attachments/#{receipt_id}/#{item_index}/#{index}"
          )
        else
          descriptor
        end
      end)

    %{message | attachments: attachments}
  end

  def download(scope, receipt_id, item_index, attachment_index) do
    with true <- valid_locator?(receipt_id, item_index, attachment_index),
         %PhoenixCRM.Message{} = message <-
           Repo.one(
             from(m in PhoenixCRM.Message,
               where:
                 fragment("?->>'receipt_id' = ?", m.source, ^receipt_id) and
                   fragment("?->>'item_index' = ?", m.source, ^to_string(item_index))
             )
           ),
         {:ok, _} <- PauseAiCa.Outreach.Mailboxes.fetch(scope, message.mailbox_ref),
         descriptor when is_map(descriptor) <-
           Enum.find(message.attachments, fn item ->
             (value(item, :attachment_index) || value(item, :index)) == attachment_index
           end),
         path = blob_path(receipt_id, item_index, attachment_index),
         true <- File.regular?(path) do
      {:ok,
       %{
         path: path,
         filename: value(descriptor, :name) || "attachment",
         content_type: value(descriptor, :content_type) || "application/octet-stream"
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_message(receipt_id, message) do
    Enum.reduce_while(message.attachments, :ok, fn descriptor, :ok ->
      index = descriptor.index
      token = message.private.attachment_tokens[index]
      path = blob_path(receipt_id, message.source_index, index)

      result =
        cond do
          File.regular?(path) -> :ok
          not is_binary(token) or token == "" -> {:error, :attachment_token_missing}
          true -> fetch(token, path)
        end

      case result do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp fetch(token, path) do
    key = Application.get_env(:pauseai_ca, :brevo_api_key)

    if not is_binary(key) or key == "",
      do: {:error, :attachment_provider_unavailable},
      else: fetch_with_key(token, path, key)
  end

  defp fetch_with_key(token, path, key) do
    File.mkdir_p!(Path.dirname(path))
    File.chmod!(Path.dirname(path), 0o700)
    part = path <> "." <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower) <> ".partial"
    File.write!(part, "", [:exclusive])
    File.chmod!(part, 0o600)

    sink = fn {:data, data}, {request, response} ->
      size = (response.private[:outreach_bytes] || 0) + byte_size(data)
      response = Req.Response.put_private(response, :outreach_bytes, size)

      if size > @max_bytes do
        {:halt, {request, Req.Response.put_private(response, :outreach_overflow, true)}}
      else
        if response.status == 200, do: File.write!(part, data, [:append])
        {:cont, {request, response}}
      end
    end

    opts = [
      headers: [{"api-key", key}],
      into: sink,
      decode_body: false,
      retry: false,
      redirect: false,
      receive_timeout: 20_000
    ]

    opts = Keyword.merge(opts, Application.get_env(:pauseai_ca, :outreach_brevo_req_options, []))

    try do
      url =
        "https://api.brevo.com/v3/inbound/attachments/" <>
          URI.encode(token, &URI.char_unreserved?/1)

      case Req.get(url, opts) do
        {:ok, %{status: 200, private: private}} ->
          if private[:outreach_overflow] do
            {:error, :attachment_too_large}
          else
            File.rename!(part, path)
            :ok
          end

        {:ok, _} ->
          {:error, :attachment_provider_rejected}

        {:error, _} ->
          {:error, :attachment_fetch_failed}
      end
    after
      File.rm(part)
    end
  end

  defp valid_locator?(id, item, attachment) do
    match?({:ok, _}, Ecto.UUID.cast(id)) and is_integer(item) and item in 0..99 and
      is_integer(attachment) and attachment in 0..24
  end

  defp blob_path(id, item, attachment) do
    key = :crypto.hash(:sha256, "#{id}:#{item}:#{attachment}") |> Base.encode16(case: :lower)
    Path.join(Application.fetch_env!(:pauseai_ca, :outreach_attachment_dir), key <> ".blob")
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
