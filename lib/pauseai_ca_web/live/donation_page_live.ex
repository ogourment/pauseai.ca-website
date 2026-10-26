defmodule PauseAiCaWeb.DonationPageLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Donations.Pages

  @fields [
    {"title", gettext_noop("Page title")},
    {"lead", gettext_noop("Introduction")},
    {"brochure_label", gettext_noop("Brochure link label")},
    {"campaign_heading", gettext_noop("Campaign heading")},
    {"campaign_body", gettext_noop("Campaign description")},
    {"cta_label", gettext_noop("Donation button label")},
    {"account_requirement", gettext_noop("Account requirement")},
    {"proposal_label", gettext_noop("Proposal link label")},
    {"unavailable_note", gettext_noop("Campaign unavailable message")},
    {"interac_heading", gettext_noop("Interac heading")},
    {"interac_body", gettext_noop("Interac instructions")},
    {"recipient_label", gettext_noop("Recipient label")},
    {"allocation_heading", gettext_noop("Budget heading")},
    {"allocation_note", gettext_noop("Budget explanation")},
    {"remaining_heading", gettext_noop("Remaining budget heading")},
    {"remaining_note", gettext_noop("Remaining budget explanation")},
    {"gift_label", gettext_noop("Suggested gift label")},
    {"gift_note", gettext_noop("Suggested gift explanation")},
    {"gift_invalid", gettext_noop("Invalid gift amount message")},
    {"funding_unknown", gettext_noop("Funding unavailable message")},
    {"projection_note", gettext_noop("Projection explanation")},
    {"remaining_label", gettext_noop("Remaining amount label")},
    {"covered_label", gettext_noop("Covered amount label")},
    {"toward_label", gettext_noop("Contribution label")},
    {"after_gift_label", gettext_noop("After gift label")},
    {"complete_note", gettext_noop("Budget covered message")},
    {"budget_label", gettext_noop("Total budget label")}
  ]

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    case Pages.get_or_create(socket.assigns.current_scope) do
      {:ok, page} ->
        {:ok,
         socket
         |> assign(
           locale: locale,
           page_title: gettext("Donation page"),
           edition: locale,
           fields: @fields,
           copy_groups: [
             {gettext_noop("Campaign links and help"),
              ~w(brochure_label account_requirement proposal_label unavailable_note)},
             {gettext_noop("Budget and gift labels"),
              ~w(allocation_heading allocation_note remaining_heading remaining_note gift_label gift_note gift_invalid funding_unknown projection_note remaining_label covered_label toward_label after_gift_label complete_note budget_label)},
             {gettext_noop("Interac instructions"),
              ~w(interac_heading interac_body recipient_label)}
           ],
           error: nil,
           stale: false,
           dirty: false,
           preview: nil,
           preview_gift_minor: 0,
           preview_gift_value: "0",
           preview_gift_error: nil,
           preview_funding_minor: nil,
           preview_funding_value: "",
           preview_funding_error: nil,
           recovery: nil,
           status: gettext("Saved")
         )
         |> load(page)}

      _ ->
        {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if Pages.permitted?(socket.assigns.current_scope) do
      dispatch(event, params, socket)
    else
      {:noreply,
       socket
       |> assign(payload: %{}, preview: nil, recovery: nil)
       |> redirect(to: ~p"/dashboard")}
    end
  end

  defp dispatch("edit", %{"page" => values}, socket),
    do: {:noreply, edit(socket, values)}

  defp dispatch("edition", %{"edition" => edition}, socket) when edition in ["en", "fr"],
    do: {:noreply, assign(socket, edition: edition)}

  defp dispatch(
         "preview-gift",
         %{"gift" => %{"amount" => value}},
         %{assigns: %{preview: preview}} = socket
       )
       when is_map(preview) do
    case PauseAiCaWeb.DonationPageContent.gift_amount_minor(value) do
      {:ok, amount} ->
        {:noreply,
         assign(socket,
           preview_gift_minor: amount,
           preview_gift_value: value,
           preview_gift_error: nil
         )}

      :error ->
        {:noreply,
         assign(socket,
           preview_gift_value: value,
           preview_gift_error:
             get_in(preview, ["editions", socket.assigns.edition, "gift_invalid"])
         )}
    end
  end

  defp dispatch(
         "preview-funding",
         %{"funding" => %{"amount" => value}},
         %{assigns: %{preview: preview}} = socket
       )
       when is_map(preview) do
    case PauseAiCaWeb.DonationPageContent.gift_amount_minor(value) do
      {:ok, amount} ->
        {:noreply,
         assign(socket,
           preview_funding_minor: if(value == "", do: nil, else: amount),
           preview_funding_value: value,
           preview_funding_error: nil
         )}

      :error ->
        {:noreply,
         assign(socket,
           preview_funding_value: value,
           preview_funding_error:
             gettext("Enter a non-negative CAD amount with at most two decimal places.")
         )}
    end
  end

  defp dispatch("submit", %{"page" => values, "intent" => "preview"}, socket) do
    socket = edit(socket, values)

    case Pages.preview(socket.assigns.current_scope, socket.assigns.payload) do
      {:ok, payload} -> {:noreply, assign(socket, preview: payload, error: nil)}
      {:error, error} -> {:noreply, failed(socket, error)}
    end
  end

  defp dispatch("submit", %{"page" => values, "intent" => "publish"}, socket),
    do: dispatch("publish", %{}, edit(socket, values))

  defp dispatch("submit", %{"page" => values, "intent" => intent}, socket)
       when is_binary(intent) do
    case String.split(intent, ":") do
      [action | ids]
      when action in [
             "stage-add",
             "stage-remove",
             "stage-up",
             "stage-down",
             "bucket-add",
             "bucket-remove",
             "bucket-up",
             "bucket-down"
           ] ->
        params = Enum.zip(["stage", "bucket"], ids) |> Map.new()
        dispatch(action, params, edit(socket, values))

      _ ->
        save(socket, values)
    end
  end

  defp dispatch("submit", %{"page" => values}, socket), do: save(socket, values)

  defp dispatch("publish", _, %{assigns: %{dirty: true}} = socket),
    do: {:noreply, assign(socket, error: gettext("Save your changes before publishing."))}

  defp dispatch("publish", _, socket) do
    case Pages.publish(socket.assigns.current_scope, socket.assigns.page) do
      {:ok, page} ->
        {:noreply,
         socket
         |> load(page)
         |> assign(status: gettext("Published"))
         |> push_event("donation-draft-saved", %{})}

      {:error, error} ->
        {:noreply, failed(socket, error)}
    end
  end

  defp dispatch("reload", _, socket) do
    case Pages.get_or_create(socket.assigns.current_scope) do
      {:ok, page} -> {:noreply, socket |> load(page) |> push_event("donation-draft-saved", %{})}
      {:error, error} -> {:noreply, failed(socket, error)}
    end
  end

  defp dispatch("restore", %{"id" => id}, socket) do
    case Pages.restore(socket.assigns.current_scope, socket.assigns.page, id) do
      {:ok, page} ->
        {:noreply,
         socket
         |> load(page)
         |> assign(status: gettext("Restored to draft"))
         |> push_event("donation-draft-saved", %{})}

      {:error, error} ->
        {:noreply, failed(socket, error)}
    end
  end

  defp dispatch("stage-add", _, socket) do
    stage = %{
      "id" => Ecto.UUID.generate(),
      "label_en" => "",
      "label_fr" => "",
      "target_minor" => 0,
      "buckets" => []
    }

    {:noreply,
     mutate(socket, Map.update(socket.assigns.payload, "stages", [stage], &(&1 ++ [stage])))}
  end

  defp dispatch(action, %{"stage" => id} = params, socket)
       when action in [
              "stage-remove",
              "stage-up",
              "stage-down",
              "bucket-add",
              "bucket-remove",
              "bucket-up",
              "bucket-down"
            ] do
    stages = socket.assigns.payload["stages"] || []
    index = Enum.find_index(stages, &(&1["id"] == id))

    updated =
      cond do
        is_nil(index) ->
          stages

        action == "stage-remove" ->
          List.delete_at(stages, index)

        action in ["stage-up", "stage-down"] ->
          move(stages, index, if(action == "stage-up", do: -1, else: 1))

        true ->
          List.update_at(stages, index, fn stage ->
            buckets = stage["buckets"] || []
            bucket_index = Enum.find_index(buckets, &(&1["id"] == params["bucket"]))

            buckets =
              cond do
                action == "bucket-add" ->
                  buckets ++
                    [
                      %{
                        "id" => Ecto.UUID.generate(),
                        "label_en" => "",
                        "label_fr" => "",
                        "amount_minor" => 0
                      }
                    ]

                is_nil(bucket_index) ->
                  buckets

                action == "bucket-remove" ->
                  List.delete_at(buckets, bucket_index)

                true ->
                  move(buckets, bucket_index, if(action == "bucket-up", do: -1, else: 1))
              end

            Map.put(stage, "buckets", buckets)
          end)
      end

    {:noreply, mutate(socket, Map.put(socket.assigns.payload, "stages", updated))}
  end

  defp dispatch("recover-offer", %{"form_query" => query, "revision" => revision}, socket)
       when is_binary(query) and byte_size(query) <= 500_000 do
    values = Plug.Conn.Query.decode(query)["page"] || %{}
    recovered = edit(socket, values).assigns.payload

    recovery =
      if recovered != socket.assigns.payload, do: %{payload: recovered, revision: revision}

    {:noreply, assign(socket, recovery: recovery)}
  end

  defp dispatch("recover-offer", %{"payload" => payload, "revision" => revision}, socket)
       when is_map(payload) do
    recovery = if payload != socket.assigns.payload, do: %{payload: payload, revision: revision}
    {:noreply, assign(socket, recovery: recovery)}
  end

  defp dispatch("recover", _, %{assigns: %{recovery: recovery}} = socket) when is_map(recovery) do
    {:noreply,
     socket
     |> assign(
       payload: recovery.payload,
       recovery: nil,
       dirty: true,
       stale: recovery.revision != socket.assigns.page.revision,
       status: gettext("Unsaved changes"),
       preview: nil
     )}
  end

  defp dispatch("discard-recovery", _, socket),
    do: {:noreply, socket |> assign(recovery: nil) |> push_event("donation-draft-saved", %{})}

  defp dispatch(_, _, socket), do: {:noreply, socket}

  defp move(list, index, offset) do
    target = index + offset

    if target >= 0 && target < length(list) do
      value = Enum.at(list, index)
      list |> List.delete_at(index) |> List.insert_at(target, value)
    else
      list
    end
  end

  defp save(socket, values) do
    socket = edit(socket, values)

    case Pages.save(socket.assigns.current_scope, socket.assigns.page, socket.assigns.payload) do
      {:ok, page} -> {:noreply, socket |> load(page) |> push_event("donation-draft-saved", %{})}
      {:error, error} -> {:noreply, failed(socket, error)}
    end
  end

  defp edit(socket, values) do
    values =
      values |> strip_form_metadata() |> Map.take(["editions", "links", "display", "stages"])

    values = if values["stages"], do: Map.update!(values, "stages", &parse_stages/1), else: values

    values =
      if values["display"], do: Map.update!(values, "display", &normalize_display/1), else: values

    mutate(socket, deep_merge(socket.assigns.payload, values))
  end

  defp mutate(socket, payload) do
    dirty = payload != socket.assigns.page.payload

    assign(socket,
      payload: payload,
      dirty: dirty,
      preview: nil,
      status: if(dirty, do: gettext("Unsaved changes"), else: gettext("Saved"))
    )
  end

  # LiveView annotates untouched inputs for validation; these are never authored content.
  defp strip_form_metadata(values) when is_map(values) do
    values
    |> Enum.reject(fn {key, _} -> is_binary(key) and String.starts_with?(key, "_unused_") end)
    |> Map.new(fn {key, value} -> {key, strip_form_metadata(value)} end)
  end

  defp strip_form_metadata(values) when is_list(values),
    do: Enum.map(values, &strip_form_metadata/1)

  defp strip_form_metadata(value), do: value

  defp normalize_display(display) do
    display
    |> Map.update("show_remaining_above", true, &(&1 in [true, "true"]))
    |> Map.update("remaining_threshold_percent", 50, fn value ->
      case Integer.parse(to_string(value)) do
        {number, ""} -> number
        _ -> value
      end
    end)
  end

  defp parse_stages(stages) do
    stages
    |> ordered_values()
    |> Enum.map(fn stage ->
      stage
      |> Map.take(["id", "label_en", "label_fr"])
      |> Map.put("target_minor", minor(stage["target_cad"]))
      |> Map.put(
        "buckets",
        stage
        |> Map.get("buckets", %{})
        |> ordered_values()
        |> Enum.map(fn bucket ->
          bucket
          |> Map.take(["id", "label_en", "label_fr"])
          |> Map.put("amount_minor", minor(bucket["amount_cad"]))
        end)
      )
    end)
  end

  defp ordered_values(values) when is_list(values), do: values

  defp ordered_values(values) when is_map(values),
    do:
      values |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end) |> Enum.map(&elem(&1, 1))

  defp ordered_values(_), do: []

  defp minor(value) when is_binary(value) and byte_size(value) <= 24 do
    if Regex.match?(~r/\A[0-9]+(?:\.[0-9]{1,2})?\z/, value) do
      value |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer()
    else
      value
    end
  end

  defp minor(value), do: value

  defp cad(value) when is_integer(value),
    do: value |> Decimal.new() |> Decimal.div(100) |> Decimal.to_string(:normal)

  defp cad(value), do: value || ""

  defp stage_total(stage),
    do:
      Enum.reduce(stage["buckets"] || [], 0, fn bucket, total ->
        if is_integer(bucket["amount_minor"]), do: total + bucket["amount_minor"], else: total
      end)

  defp deep_merge(left, right),
    do:
      Map.merge(left, right, fn _, old, new ->
        if is_map(old) and is_map(new), do: deep_merge(old, new), else: new
      end)

  defp load(socket, page) do
    case Pages.history(socket.assigns.current_scope) do
      {:ok, history} ->
        assign(socket,
          page: page,
          payload: page.payload,
          history: history,
          dirty: false,
          stale: false,
          error: nil,
          preview: nil,
          recovery: nil,
          status: gettext("Saved")
        )

      _ ->
        redirect(socket, to: ~p"/dashboard")
    end
  end

  defp failed(socket, :stale),
    do:
      assign(socket,
        stale: true,
        error:
          gettext(
            "Another editor saved a newer version. Your fields are retained. Reload only when you are ready to discard your edits."
          )
      )

  defp failed(socket, :unauthorized), do: redirect(socket, to: ~p"/dashboard")

  defp failed(socket, %Ecto.Changeset{} = changeset) do
    errors =
      Enum.map(changeset.errors, fn {_field, {_message, opts}} ->
        gettext("Review %{field}.", field: field_label(Keyword.get(opts, :path, "")))
      end)

    assign(socket, error: errors |> Enum.uniq() |> Enum.join(" "))
  end

  defp failed(socket, _),
    do:
      assign(socket,
        error: gettext("Could not save. Your changes are retained.")
      )

  defp field_label(path) do
    case String.split(to_string(path), ".") do
      ["editions", edition, key] ->
        language = if edition == "fr", do: gettext("French"), else: gettext("English")

        label =
          Enum.find_value(@fields, gettext("Page copy"), fn {field, label} ->
            if field == key, do: Gettext.gettext(PauseAiCaWeb.Gettext, label)
          end)

        "#{language} · #{label}"

      ["links", "campaign"] ->
        gettext("Campaign URL")

      ["links", "brochure"] ->
        gettext("Brochure URL")

      ["display", "remaining_threshold_percent"] ->
        gettext("Remaining budget threshold (%)")

      ["display" | _] ->
        gettext("Display settings")

      ["stages", index, "buckets", bucket | _] ->
        gettext("Stage %{stage}, bucket %{bucket}",
          stage: display_index(index),
          bucket: display_index(bucket)
        )

      ["stages", index | _] ->
        gettext("Stage %{number}", number: display_index(index))

      ["stages"] ->
        gettext("Funding stages")

      _ ->
        gettext("Budget or link settings")
    end
  end

  defp display_index(index) do
    case Integer.parse(index) do
      {number, ""} -> number + 1
      _ -> "?"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="donations"
    >
      <section id="donation-page-editor" class="mx-auto max-w-5xl space-y-6 px-5 py-8">
        <header class="space-y-3">
          <h1 class="font-heading text-3xl">{gettext("Donation page")}</h1>
          <p>
            {gettext(
              "Edit both language editions. Saving keeps a draft; publishing changes the public page."
            )}
          </p>
          <div class="flex flex-wrap items-center gap-3">
            <button
              type="submit"
              form="donation-page-form"
              name="intent"
              value="save"
              class={button_class(true)}
              disabled={@stale}
            >{gettext("Save draft")}</button>
            <button
              type="submit"
              form="donation-page-form"
              name="intent"
              value="preview"
              class={button_class()}
            >{gettext("Preview")}</button>
            <button
              id="donation-publish"
              type="submit"
              form="donation-page-form"
              name="intent"
              value="publish"
              disabled={@dirty || @stale}
              class={button_class()}
            >{gettext("Publish")}</button>
            <span id="donation-save-status" role="status" aria-live="polite">{@status}</span>
          </div>
          <nav
            aria-label={gettext("Editor sections")}
            class="flex flex-wrap gap-4 text-sm underline underline-offset-4"
          >
            <a href="#donation-page-form">{gettext("Page copy")}</a>
            <a href="#donation-stages">{gettext("Funding stages")}</a>
            <a href="#donation-links">{gettext("Links")}</a>
            <a href="#donation-display">{gettext("Display settings")}</a>
            <a href="#donation-history">{gettext("Revision history")}</a>
          </nav>
          <p class="text-sm">
            {gettext("Draft revision")}: {@page.revision} · {gettext("Published revision")}: {@page.published_revision ||
              gettext("None")}
          </p>
        </header>
        <div
          :if={@error}
          id="donation-editor-error"
          role="alert"
          class="rounded-lg border border-red-400 bg-red-50 p-4"
        >
          {@error}
        </div>
        <section
          :if={@stale}
          id="donation-conflict"
          class="rounded-lg border border-amber-400 bg-amber-50 p-4"
        >
          <p>
            {gettext(
              "Your edits remain in the form. Reloading replaces them with the latest saved draft."
            )}
          </p>
          <button
            type="button"
            phx-click="reload"
            data-confirm={gettext("Discard your edits and load the latest saved draft?")}
            class={[button_class(), "mt-3"]}
          >{gettext("Discard edits and reload")}</button>
        </section>
        <section :if={@recovery} id="donation-recovery" class="rounded-lg border border-amber-400 p-4">
          <p>{gettext("This tab has unsaved edits from an earlier visit.")}</p>
          <div class="mt-3 flex flex-wrap gap-3">
            <button type="button" phx-click="recover" class={button_class()}>{gettext("Recover edits")}</button>
            <button type="button" phx-click="discard-recovery" class={button_class()}>{gettext(
              "Discard recovered edits"
            )}</button>
          </div>
        </section>
        <.form
          for={to_form(%{}, as: "page")}
          id="donation-page-form"
          phx-change="edit"
          phx-submit="submit"
          phx-hook=".DonationDraft"
          data-dirty={to_string(@dirty)}
          data-payload={Jason.encode!(@payload)}
          data-revision={@page.revision}
          data-draft-key={"pauseai:donation-page-draft:" <> @current_scope.user.id}
        >
          <div class="mb-5 flex flex-wrap gap-3" role="group" aria-label={gettext("Language edition")}>
            <button
              :for={edition <- ["en", "fr"]}
              id={"donation-edition-#{edition}"}
              type="button"
              phx-click="edition"
              phx-value-edition={edition}
              aria-pressed={to_string(@edition == edition)}
              class={button_class(@edition == edition)}
            >{if edition == "en", do: "English", else: "Français"}</button>
          </div>
          <fieldset
            :for={edition <- ["en", "fr"]}
            hidden={@edition != edition}
            class="space-y-5 rounded-xl border border-stone-300 bg-white p-5"
          >
            <legend class="px-2 font-semibold">
              {if edition == "en", do: "English", else: "Français"}
            </legend>
            <.input
              :for={
                {key, label} <-
                  Enum.filter(@fields, fn {key, _} ->
                    key in ~w(title lead campaign_heading campaign_body cta_label)
                  end)
              }
              id={"donation-#{edition}-#{key}"}
              name={"page[editions][#{edition}][#{key}]"}
              type="textarea"
              label={Gettext.gettext(PauseAiCaWeb.Gettext, label)}
              aria-label={Gettext.gettext(PauseAiCaWeb.Gettext, label)}
              value={get_in(@payload, ["editions", edition, key]) || ""}
              phx-debounce="300"
            />
            <details
              :for={{group, keys} <- @copy_groups}
              class="rounded-lg border border-stone-300 bg-stone-50 p-4"
            >
              <summary class="cursor-pointer font-semibold">
                {Gettext.gettext(PauseAiCaWeb.Gettext, group)}
              </summary>
              <div class="mt-4 space-y-4">
                <.input
                  :for={{key, label} <- Enum.filter(@fields, fn {key, _} -> key in keys end)}
                  id={"donation-#{edition}-#{key}"}
                  name={"page[editions][#{edition}][#{key}]"}
                  type="textarea"
                  label={Gettext.gettext(PauseAiCaWeb.Gettext, label)}
                  aria-label={Gettext.gettext(PauseAiCaWeb.Gettext, label)}
                  value={get_in(@payload, ["editions", edition, key]) || ""}
                  phx-debounce="300"
                />
              </div>
            </details>
          </fieldset>
          <section id="donation-stages" class="mt-6 space-y-4">
            <h2 class="text-2xl font-semibold">{gettext("Funding stages")}</h2>
            <p>
              {gettext(
                "Each stage is a complete budget at its cumulative target. Bucket order breaks allocation ties. Stage targets must increase."
              )}
            </p>
            <details
              :for={{stage, stage_index} <- Enum.with_index(@payload["stages"] || [])}
              id={"donation-stage-#{stage["id"]}"}
              class="rounded-xl border border-stone-300 bg-white p-5"
              open={stage_index == 0}
            >
              <summary class="cursor-pointer font-semibold">
                <span>{if stage["label_#{@edition}"] in [nil, ""],
                  do: gettext("New stage"),
                  else: stage["label_#{@edition}"]}</span>
                <span class="mt-1 block text-sm font-normal">{gettext("Stage target")}: {cad(
                  stage["target_minor"]
                )} CAD · {gettext("Bucket total")}: {cad(stage_total(stage))} CAD</span>
              </summary>
              <div class="mt-4 space-y-4">
                <.input type="hidden" name={"page[stages][#{stage_index}][id]"} value={stage["id"]} />
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    name={"page[stages][#{stage_index}][label_en]"}
                    label={gettext("Stage name — English")}
                    value={stage["label_en"]}
                  />
                  <.input
                    name={"page[stages][#{stage_index}][label_fr]"}
                    label={gettext("Stage name — French")}
                    value={stage["label_fr"]}
                  />
                </div>
                <.input
                  name={"page[stages][#{stage_index}][target_cad]"}
                  type="number"
                  step="0.01"
                  min="0.01"
                  label={gettext("Cumulative stage target (CAD)")}
                  value={cad(stage["target_minor"])}
                />
                <p class="font-semibold">
                  {gettext("Bucket total")}: {cad(stage_total(stage))} CAD · {gettext("Stage target")}: {cad(
                    stage["target_minor"]
                  )} CAD
                </p>
                <p :if={stage_total(stage) != stage["target_minor"]} role="alert" class="text-red-800">
                  {gettext("The bucket total must equal this stage target.")}
                </p>
                <div class="flex flex-wrap gap-2">
                  <button
                    type="submit"
                    name="intent"
                    value={"stage-up:" <> stage["id"]}
                    formnovalidate
                    data-action="stage-up"
                    disabled={stage_index == 0}
                    class={button_class()}
                  >{gettext("Move stage up")}</button>
                  <button
                    type="submit"
                    name="intent"
                    value={"stage-down:" <> stage["id"]}
                    formnovalidate
                    data-action="stage-down"
                    disabled={stage_index == length(@payload["stages"]) - 1}
                    class={button_class()}
                  >{gettext("Move stage down")}</button>
                  <button
                    type="submit"
                    name="intent"
                    value={"stage-remove:" <> stage["id"]}
                    formnovalidate
                    data-action="stage-remove"
                    data-confirm={gettext("Remove this stage and its buckets from the draft?")}
                    class={button_class()}
                  >{gettext("Remove stage")}</button>
                </div>
                <article
                  :for={{bucket, bucket_index} <- Enum.with_index(stage["buckets"] || [])}
                  id={"donation-bucket-#{bucket["id"]}"}
                  class="space-y-3 rounded-lg border border-stone-300 bg-stone-50 p-4"
                >
                  <.input
                    type="hidden"
                    name={"page[stages][#{stage_index}][buckets][#{bucket_index}][id]"}
                    value={bucket["id"]}
                  />
                  <div class="grid gap-4 sm:grid-cols-2">
                    <.input
                      name={"page[stages][#{stage_index}][buckets][#{bucket_index}][label_en]"}
                      label={gettext("Bucket name — English")}
                      value={bucket["label_en"]}
                    />
                    <.input
                      name={"page[stages][#{stage_index}][buckets][#{bucket_index}][label_fr]"}
                      label={gettext("Bucket name — French")}
                      value={bucket["label_fr"]}
                    />
                  </div>
                  <.input
                    name={"page[stages][#{stage_index}][buckets][#{bucket_index}][amount_cad]"}
                    type="number"
                    step="0.01"
                    min="0.01"
                    label={gettext("Bucket budget (CAD)")}
                    value={cad(bucket["amount_minor"])}
                  />
                  <div class="flex flex-wrap gap-2">
                    <button
                      type="submit"
                      name="intent"
                      value={"bucket-up:" <> stage["id"] <> ":" <> bucket["id"]}
                      formnovalidate
                      data-action="bucket-up"
                      disabled={bucket_index == 0}
                      class={button_class()}
                    >{gettext("Move bucket up")}</button>
                    <button
                      type="submit"
                      name="intent"
                      value={"bucket-down:" <> stage["id"] <> ":" <> bucket["id"]}
                      formnovalidate
                      data-action="bucket-down"
                      disabled={bucket_index == length(stage["buckets"]) - 1}
                      class={button_class()}
                    >{gettext("Move bucket down")}</button>
                    <button
                      type="submit"
                      name="intent"
                      value={"bucket-remove:" <> stage["id"] <> ":" <> bucket["id"]}
                      formnovalidate
                      data-action="bucket-remove"
                      class={button_class()}
                    >{gettext("Remove bucket")}</button>
                  </div>
                </article>
                <button
                  type="submit"
                  name="intent"
                  value={"bucket-add:" <> stage["id"]}
                  formnovalidate
                  data-action="bucket-add"
                  class={button_class()}
                >{gettext("Add bucket")}</button>
              </div>
            </details>
            <button
              type="submit"
              name="intent"
              value="stage-add"
              formnovalidate
              data-action="stage-add"
              class={button_class()}
            >{gettext("Add stage")}</button>
          </section>
          <section
            id="donation-links"
            class="mt-6 space-y-4 rounded-xl border border-stone-300 bg-white p-5"
          >
            <h2 class="text-xl font-semibold">{gettext("Links")}</h2>
            <.input
              id="donation-brochure-url"
              name="page[links][brochure]"
              type="url"
              label={gettext("Brochure URL")}
              value={get_in(@payload, ["links", "brochure"])}
              phx-debounce="300"
            />
            <.input
              id="donation-campaign-url"
              name="page[links][campaign]"
              type="url"
              label={gettext("Campaign URL")}
              value={get_in(@payload, ["links", "campaign"])}
              phx-debounce="300"
            />
          </section>
          <section
            id="donation-display"
            class="mt-6 space-y-4 rounded-xl border border-stone-300 bg-white p-5"
          >
            <h2 class="text-xl font-semibold">{gettext("Display settings")}</h2>
            <p>
              {gettext(
                "Show the remaining budget when recorded funding is strictly above this percentage of the full budget."
              )}
            </p>
            <p class="text-sm text-stone-600">
              {gettext(
                "The threshold applies separately to the active stage budget and to the full programme budget."
              )}
            </p>
            <.input type="hidden" name="page[display][mode]" value="remaining_after_threshold" />
            <.input
              id="donation-threshold"
              name="page[display][remaining_threshold_percent]"
              type="number"
              min="0"
              max="100"
              step="1"
              label={gettext("Remaining budget threshold (%)")}
              value={get_in(@payload, ["display", "remaining_threshold_percent"])}
            />
            <.input
              id="donation-remaining-enabled"
              name="page[display][show_remaining_above]"
              type="checkbox"
              label={gettext("Switch to remaining buckets above the threshold")}
              value={get_in(@payload, ["display", "show_remaining_above"])}
            />
          </section>
        </.form>
        <section
          :if={@preview}
          id="donation-preview"
          class="space-y-4 rounded-xl border-2 border-brand bg-white p-5"
        >
          <h2 class="text-2xl font-semibold">{gettext("Draft preview")}</h2>
          <p>{gettext("Preview only. No publication, payment or message is created.")}</p>
          <p class="rounded-lg border border-amber-400 bg-amber-50 p-3">
            {gettext(
              "Illustrative preview only. The funding amount below is synthetic and is never saved as provider data."
            )}
          </p>
          <.form
            for={to_form(%{}, as: "funding")}
            id="donation-preview-funding-form"
            phx-change="preview-funding"
            phx-submit="preview-funding"
          >
            <.input
              id="donation-preview-funding"
              name="funding[amount]"
              type="number"
              min="0"
              max="999999999.99"
              step="0.01"
              label={gettext("Illustrative funding (CAD)")}
              value={@preview_funding_value}
              errors={if @preview_funding_error, do: [@preview_funding_error], else: []}
            />
            <p class="mt-2 text-sm text-stone-600">
              {gettext("Leave blank to preview unknown funding.")}
            </p>
          </.form>
          <PauseAiCaWeb.DonationPageContent.content
            page={@preview}
            locale={@edition}
            preview_mode={true}
            gift_minor={@preview_gift_minor}
            gift_value={@preview_gift_value}
            input_error={@preview_gift_error}
            preview_event="preview-gift"
            observation={
              if is_integer(@preview_funding_minor),
                do: %{amount_minor: @preview_funding_minor, currency: "CAD"},
                else: nil
            }
          />
        </section>
        <details id="donation-history" class="rounded-xl border border-stone-300 bg-white p-5">
          <summary class="cursor-pointer text-xl font-semibold">
            {gettext("Revision history")}
          </summary>
          <ol class="mt-4 space-y-3">
            <li
              :for={revision <- @history}
              class="flex flex-wrap items-center justify-between gap-3 border-t pt-3"
            >
              <span>{gettext("Revision")} {revision.revision} · {revision_action(revision.action)} · {Calendar.strftime(
                revision.inserted_at,
                "%Y-%m-%d %H:%M UTC"
              )}</span>
              <button
                type="button"
                phx-click="restore"
                phx-value-id={revision.id}
                data-confirm={
                  gettext(
                    "Replace the current draft with this revision? The public page stays unchanged until Publish."
                  )
                }
                class={button_class()}
              >{gettext("Restore to draft")}</button>
            </li>
          </ol>
        </details>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".DonationDraft">
        export default {
          mounted() {
            this.key = this.el.dataset.draftKey
            this.persist = () => {
              this.localDirty = true
              try { sessionStorage.setItem(this.key, JSON.stringify({form_query: new URLSearchParams(new FormData(this.el)).toString(), revision: Number(this.el.dataset.revision)})) } catch (_) {}
            }
            this.el.addEventListener("input", this.persist)
            this.el.addEventListener("change", this.persist)
            this.unload = event => {
              if (this.localDirty || this.el.dataset.dirty === "true") { event.preventDefault(); event.returnValue = "" }
            }
            window.addEventListener("beforeunload", this.unload)
            this.handleEvent("donation-draft-saved", () => { this.localDirty = false; sessionStorage.removeItem(this.key) })
            try {
              const draft = JSON.parse(sessionStorage.getItem(this.key) || "null")
              if (draft) this.pushEvent("recover-offer", draft)
            } catch (_) {}
          },
          updated() {
            if (this.el.dataset.dirty !== "true") return
            try { sessionStorage.setItem(this.key, JSON.stringify({payload: JSON.parse(this.el.dataset.payload), revision: Number(this.el.dataset.revision)})) } catch (_) {}
          },
          destroyed() {
            window.removeEventListener("beforeunload", this.unload)
            this.el.removeEventListener("input", this.persist)
            this.el.removeEventListener("change", this.persist)
          }
        }
      </script>
    </Layouts.management>
    """
  end

  defp button_class(primary \\ false),
    do: [
      "inline-flex min-h-11 items-center justify-center rounded-lg border px-4 py-2 font-semibold disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand",
      if(primary,
        do: "border-brand bg-brand text-stone-950 hover:bg-brand-strong",
        else: "border-stone-400 bg-white text-stone-950 hover:bg-stone-100"
      )
    ]

  defp revision_action("created"), do: gettext("Created")
  defp revision_action("saved"), do: gettext("Saved")
  defp revision_action("published"), do: gettext("Published")
  defp revision_action("restored"), do: gettext("Restored to draft")
  defp revision_action(_), do: gettext("Updated")
end
