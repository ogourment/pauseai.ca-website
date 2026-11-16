defmodule PauseAiCaWeb.AssistantInstructionsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Assistant.Instructions
  alias PhoenixAgentAssistant.InstructionEditor

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
      InstructionEditor.save(Instructions, socket.assigns.current_scope, socket.assigns, source)

    result(socket, result, gettext("Draft saved"))
  end

  defp action("publish", _, %{assigns: %{dirty: false}} = socket) do
    result =
      InstructionEditor.publish(Instructions, socket.assigns.current_scope, socket.assigns)

    result(socket, result, gettext("Instructions published"))
  end

  defp action("publish", _, socket),
    do: {:noreply, assign(socket, error: gettext("Save your changes before publishing."))}

  defp action(_, _, socket), do: {:noreply, socket}

  defp edit(socket, source) do
    case InstructionEditor.edit(socket.assigns, source) do
      {:ok, changes} ->
        socket
        |> assign(changes)
        |> assign(
          status: if(changes.dirty, do: gettext("Unsaved changes"), else: saved_status(socket))
        )

      {:error, :invalid_source} ->
        assign(socket, error: gettext("Use between 1 and 24,000 bytes of instructions."))
    end
  end

  defp saved_status(%{assigns: %{dirty: true}}), do: gettext("Draft saved")
  defp saved_status(socket), do: socket.assigns.status

  defp result(socket, {:ok, state}, status),
    do: {:noreply, socket |> assign(state) |> assign(status: status, error: nil)}

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
    case InstructionEditor.load(Instructions, socket.assigns.current_scope) do
      {:ok, state} -> assign(socket, state)
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
        <InstructionEditor.editor
          instruction={@instruction}
          form={@form}
          history={@history}
          dirty={@dirty}
          connected={connected?(@socket)}
          status={@status}
          error={@error}
          class="space-y-5"
          button_class="crm-button"
          fieldset_class="space-y-4"
          revision_label={gettext("Draft revision %{revision}", revision: @instruction.revision)}
          published_label={
            if @instruction.published_revision,
              do:
                gettext("Published revision %{revision}", revision: @instruction.published_revision),
              else: gettext("Using the bundled application instructions")
          }
          labels={
            %{
              save: gettext("Save draft"),
              saving: gettext("Saving…"),
              publish: gettext("Publish saved instructions"),
              publishing: gettext("Publishing…"),
              published: gettext("Current published instructions"),
              history: gettext("Revision history")
            }
          }
        >
          <:editor>
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
          </:editor>
          <:history_entry :let={revision}>
            <article class="mt-4 space-y-2">
              <p>
                {revision.revision} · {revision_action(revision.action)} · {revision.editor_id} · {revision.inserted_at}
              </p>
              <pre class="whitespace-pre-wrap break-words">{revision.source}</pre>
            </article>
          </:history_entry>
        </InstructionEditor.editor>
      </section>
    </Layouts.management>
    """
  end
end
