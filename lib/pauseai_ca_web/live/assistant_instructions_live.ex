defmodule PauseAiCaWeb.AssistantInstructionsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Assistant.Instructions

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Instructions.permitted?(socket.assigns.current_scope) do
      if connected?(socket), do: Process.send_after(self(), :refresh_access, 15_000)

      {:ok,
       socket
       |> assign(locale: locale, page_title: gettext("Instructions"), error: nil, status: nil)
       |> reload()}
    else
      {:ok, denied(socket)}
    end
  end

  def handle_event(event, params, socket) do
    if Instructions.permitted?(socket.assigns.current_scope),
      do: action(event, params, socket),
      else: {:noreply, denied(socket)}
  end

  def handle_info(:refresh_access, socket) do
    Process.send_after(self(), :refresh_access, 15_000)

    {:noreply,
     if(Instructions.permitted?(socket.assigns.current_scope), do: socket, else: denied(socket))}
  end

  def handle_info({:markdown_editor_changed, "assistant-instruction-source", source}, socket) do
    if Instructions.permitted?(socket.assigns.current_scope),
      do: {:noreply, edit(socket, source)},
      else: {:noreply, denied(socket)}
  end

  defp action("edit", %{"instructions" => %{"source" => source}}, socket),
    do: {:noreply, edit(socket, source)}

  defp action("save", %{"instructions" => %{"source" => source}}, socket) do
    socket = edit(socket, source)

    result =
      Instructions.save(socket.assigns.current_scope, socket.assigns.instruction.revision, source)

    result(socket, result, gettext("Draft saved"))
  end

  defp action("publish", _, %{assigns: %{dirty: false}} = socket) do
    result =
      Instructions.publish(socket.assigns.current_scope, socket.assigns.instruction.revision)

    result(socket, result, gettext("Instructions published"))
  end

  defp action("publish", _, socket),
    do: {:noreply, assign(socket, error: gettext("Save your changes before publishing."))}

  defp action(_, _, socket), do: {:noreply, socket}

  defp edit(socket, source) when is_binary(source) and byte_size(source) <= 24_000 do
    dirty = source != socket.assigns.instruction.source

    assign(socket,
      form: to_form(%{"source" => source}, as: "instructions"),
      dirty: dirty,
      status: if(dirty, do: gettext("Unsaved changes"), else: saved_status(socket))
    )
  end

  defp edit(socket, _),
    do: assign(socket, error: gettext("Use between 1 and 24,000 bytes of instructions."))

  defp saved_status(%{assigns: %{dirty: true}}), do: gettext("Draft saved")
  defp saved_status(socket), do: socket.assigns.status

  defp result(socket, {:ok, _}, status),
    do: {:noreply, socket |> reload() |> assign(status: status, error: nil)}

  defp result(socket, {:error, :unauthorized}, _), do: {:noreply, denied(socket)}

  defp result(socket, {:error, :stale}, _),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext(
             "Instructions changed in another session. Your text is retained. Copy it before reloading."
           )
       )}

  defp result(socket, {:error, _}, _),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext(
             "The change could not be saved. Use between 1 and 24,000 bytes of instructions."
           )
       )}

  defp reload(socket) do
    with {:ok, instruction} <- Instructions.get(socket.assigns.current_scope),
         {:ok, history} <- Instructions.history(socket.assigns.current_scope) do
      assign(socket,
        instruction: instruction,
        history: history,
        dirty: false,
        form: to_form(%{"source" => instruction.source}, as: "instructions")
      )
    else
      {:error, :unauthorized} -> denied(socket)
    end
  end

  defp denied(socket),
    do: socket |> assign(instruction: nil, history: [], form: nil) |> redirect(to: "/")

  defp revision_action("save"), do: gettext("Draft saved")
  defp revision_action("publish"), do: gettext("Instructions published")

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="assistant"
      breadcrumb_context={
        PauseAiCaWeb.Navigation.assistant_breadcrumb_context(@current_scope, @locale)
      }
    >
      <section :if={@instruction} id="assistant-instructions" class="crm-surface space-y-5">
        <h1 class="text-2xl font-bold">{gettext("Instructions")}</h1>
        <p>
          {gettext(
            "Edit the application coaching supplied to the assistant. Save a draft, then publish it to apply it to new turns."
          )}
        </p>
        <p>
          {gettext(
            "Permissions, moderation, budgets and execution safeguards are enforced by application code."
          )}
        </p>
        <p id="assistant-instruction-revision">
          {gettext("Draft revision %{revision}", revision: @instruction.revision)} ·
          <%= if @instruction.published_revision do %>
            {gettext("Published revision %{revision}", revision: @instruction.published_revision)}
          <% else %>
            {gettext("Using the bundled application instructions")}
          <% end %>
        </p>
        <p :if={@status} id="assistant-instruction-status" role="status">{@status}</p>
        <p :if={@error} id="assistant-instruction-error" role="alert">{@error}</p>
        <.form for={@form} id="assistant-instruction-form" phx-change="edit" phx-submit="save">
          <fieldset disabled={!connected?(@socket)} class="space-y-4">
            <.live_component
              module={PhoenixMarkdownEditor.Component}
              id="assistant-instruction-source"
              source={@form[:source].value || ""}
              name="instructions[source]"
              input_attrs={[required: true, maxlength: 24_000]}
              label={gettext("Application instructions · Markdown")}
              preview_label={gettext("Preview ↗")}
              preview_title={gettext("Instructions")}
              render_preview={
                fn source ->
                  if Instructions.permitted?(@current_scope),
                    do: PauseAiCa.Mail.Render.html(source),
                    else: ""
                end
              }
              popup_blocked_message={gettext("Allow the preview window, then try again.")}
              preview_open_message={gettext("Preview opened")}
              preview_updated_message={gettext("Preview updated")}
              disconnected_message={gettext("Connection interrupted; text retained in this page.")}
              preview_error_message={gettext("Preview unavailable. Your text is retained.")}
            />
            <button
              id="assistant-instruction-save"
              type="submit"
              class="crm-button"
              phx-disable-with={gettext("Saving…")}
            >{gettext("Save draft")}</button>
          </fieldset>
        </.form>
        <button
          id="assistant-instruction-publish"
          type="button"
          phx-click="publish"
          disabled={@dirty or @instruction.revision == 0 or !connected?(@socket)}
          class="crm-button"
          phx-disable-with={gettext("Publishing…")}
        >{gettext("Publish saved instructions")}</button>
        <details :if={@instruction.published_source}>
          <summary>{gettext("Current published instructions")}</summary>
          <pre class="whitespace-pre-wrap break-words">{@instruction.published_source}</pre>
        </details>
        <details id="assistant-instruction-history">
          <summary>{gettext("Revision history")}</summary>
          <article
            :for={revision <- @history}
            id={"assistant-instruction-revision-#{revision.revision}"}
            class="mt-4 space-y-2"
          >
            <p>
              {revision.revision} · {revision_action(revision.action)} · {revision.editor_id} · {revision.inserted_at}
            </p>
            <pre class="whitespace-pre-wrap break-words">{revision.source}</pre>
          </article>
        </details>
      </section>
    </Layouts.management>
    """
  end
end
