defmodule PauseAiCaWeb.MPTemplatesLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.MPTemplates

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("MP campaign templates"),
        error: nil,
        template: nil,
        templates: [],
        history: [],
        completed_count: 0,
        payload: MPTemplates.empty_payload(),
        dirty: false,
        status: nil,
        create_form: to_form(%{"slug" => ""}, as: "campaign")
      )

    if MPTemplates.permitted?(socket.assigns.current_scope),
      do: {:ok, socket},
      else: {:ok, deny(socket)}
  end

  def handle_params(params, _, socket) do
    with true <- MPTemplates.permitted?(socket.assigns.current_scope),
         {:ok, templates} <- MPTemplates.list(socket.assigns.current_scope) do
      socket = assign(socket, templates: templates)

      case params["id"] do
        nil ->
          {:noreply, assign(socket, template: nil)}

        id ->
          case MPTemplates.get(socket.assigns.current_scope, id) do
            {:ok, template} -> {:noreply, load(socket, template)}
            _ -> {:noreply, deny(socket)}
          end
      end
    else
      _ -> {:noreply, deny(socket)}
    end
  end

  def handle_event(event, params, socket) do
    if MPTemplates.permitted?(socket.assigns.current_scope),
      do: action(event, params, socket),
      else: {:noreply, deny(socket)}
  end

  def handle_info({:markdown_editor_changed, "mp-template-" <> suffix, source}, socket) do
    locale = if suffix == "en-body", do: "en", else: if(suffix == "fr-body", do: "fr")

    if MPTemplates.permitted?(socket.assigns.current_scope) and locale in ["en", "fr"] and
         is_binary(source) do
      {:noreply,
       edit(socket, put_in(socket.assigns.payload, ["editions", locale, "body"], source))}
    else
      {:noreply, deny(socket)}
    end
  end

  defp action(event, _, %{assigns: %{template: nil}} = socket)
       when event in ["edit", "save", "publish"], do: {:noreply, socket}

  defp action("create", %{"campaign" => %{"slug" => slug}}, socket) do
    case MPTemplates.create(socket.assigns.current_scope, slug) do
      {:ok, template} ->
        {:noreply,
         push_navigate(socket,
           to: "/manage/mp-templates/#{template.id}?locale=#{socket.assigns.locale}"
         )}

      _ ->
        {:noreply,
         assign(socket,
           create_form: to_form(%{"slug" => slug}, as: "campaign"),
           error: gettext("Choose an unused slug with lowercase letters, numbers and hyphens.")
         )}
    end
  end

  defp action("edit", %{"campaign" => payload}, socket), do: {:noreply, edit(socket, payload)}

  defp action("save", %{"campaign" => payload}, socket) do
    socket = edit(socket, payload)

    result(
      socket,
      MPTemplates.save(socket.assigns.current_scope, socket.assigns.template, payload),
      gettext("Draft saved")
    )
  end

  defp action("publish", params, %{assigns: %{dirty: false, template: template}} = socket)
       when not is_nil(template),
       do:
         result(
           socket,
           MPTemplates.publish(
             socket.assigns.current_scope,
             template,
             params["author_permission"]
           ),
           gettext("Campaign template published")
         )

  defp action("publish", _, socket),
    do: {:noreply, assign(socket, error: gettext("Save your changes before publishing."))}

  defp action(_, _, socket), do: {:noreply, socket}

  defp edit(socket, values) do
    payload = PauseAiCa.MPTemplates.Payload.normalize(values)
    dirty = payload != socket.assigns.template.payload

    status =
      if dirty,
        do: gettext("Unsaved changes"),
        else: if(socket.assigns.dirty, do: gettext("Draft saved"), else: socket.assigns.status)

    assign(socket, payload: payload, dirty: dirty, status: status, error: nil)
  end

  defp result(socket, {:ok, template}, status),
    do: {:noreply, socket |> load(template) |> assign(status: status, error: nil)}

  defp result(socket, {:error, :unauthorized}, _), do: {:noreply, deny(socket)}

  defp result(socket, {:error, :stale}, _),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext(
             "This template changed in another session. Your text is retained. Copy it before reloading."
           )
       )}

  defp result(socket, {:error, :author_permission_required}, _),
    do:
      {:noreply,
       assign(socket, error: gettext("Confirm the author's permission for this publication."))}

  defp result(socket, {:error, :invalid_content}, _),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext(
             "Complete the author, HTTP or HTTPS source and both language editions within the field limits."
           )
       )}

  defp result(socket, {:error, _}, _),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext("Complete the author, source and both language editions before publishing.")
       )}

  defp load(socket, template) do
    case MPTemplates.history(socket.assigns.current_scope, template) do
      {:ok, history} ->
        assign(socket,
          template: template,
          payload: template.payload,
          dirty: false,
          history: history,
          completed_count: MPTemplates.completed_count(template.id)
        )

      _ ->
        deny(socket)
    end
  end

  defp deny(socket),
    do:
      socket
      |> assign(template: nil, templates: [], payload: %{}, history: [])
      |> redirect(to: "/")

  defp revision_action("created"), do: gettext("Created")
  defp revision_action("saved"), do: gettext("Draft saved")
  defp revision_action("published"), do: gettext("Published")

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mp_templates"
    >
      <section id="mp-templates-management" class="crm-surface space-y-6">
        <h1 class="font-heading text-2xl">{gettext("MP campaign templates")}</h1>
        <p>
          {gettext(
            "Review reusable campaign text, its purpose and public attribution before publishing a shareable version."
          )}
        </p>
        <p :if={@error} id="mp-template-error" role="alert">{@error}</p>
        <p :if={@status} id="mp-template-status" role="status">{@status}</p>
        <section :if={is_nil(@template)}>
          <.form for={@create_form} id="mp-template-create" phx-submit="create" class="space-y-3">
            <fieldset disabled={!connected?(@socket)}>
              <.input
                field={@create_form[:slug]}
                label={gettext("Campaign slug")}
                required
                maxlength="80"
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
              />
              <button type="submit" class="crm-button" phx-disable-with={gettext("Creating…")}>{gettext(
                "Create template"
              )}</button>
            </fieldset>
          </.form>
          <ul class="mt-6 space-y-3">
            <li :for={template <- @templates}>
              <.link
                navigate={"/manage/mp-templates/#{template.id}?locale=#{@locale}"}
                class="underline"
              >{template.slug}</.link>
            </li>
          </ul>
        </section>
        <section :if={@template} id="mp-template-editor" class="space-y-5">
          <p id="mp-template-editor-completed-count" class="text-sm">
            {ngettext(
              "%{count} letter sent or confirmed",
              "%{count} letters sent or confirmed",
              @completed_count
            )}
          </p>
          <p>
            <strong>{@template.slug}</strong>
            · {gettext("Draft revision %{revision}", revision: @template.revision)}
          </p>
          <.form
            for={to_form(%{}, as: "campaign")}
            id="mp-template-form"
            phx-change="edit"
            phx-submit="save"
            class="space-y-5"
          >
            <fieldset disabled={!connected?(@socket)} class="min-w-0 space-y-5">
              <.input
                id="mp-template-author"
                name="campaign[author]"
                value={@payload["author"]}
                label={gettext("Public author attribution")}
                maxlength="200"
              />
              <.input
                id="mp-template-source"
                name="campaign[source]"
                value={@payload["source"]}
                label={gettext("Public source URL")}
                type="url"
                maxlength="1000"
              />
              <fieldset :for={locale <- ["en", "fr"]} class="min-w-0 space-y-4 rounded-xl border p-4">
                <legend class="font-semibold">
                  {if locale == "en", do: gettext("English"), else: gettext("French")}
                </legend>
                <.input
                  name={"campaign[editions][#{locale}][title]"}
                  value={@payload["editions"][locale]["title"]}
                  label={gettext("Campaign title")}
                  id={"mp-template-#{locale}-title"}
                  maxlength="160"
                />
                <.input
                  name={"campaign[editions][#{locale}][purpose]"}
                  value={@payload["editions"][locale]["purpose"]}
                  label={gettext("Campaign purpose")}
                  id={"mp-template-#{locale}-purpose"}
                  type="textarea"
                  maxlength="3000"
                />
                <.input
                  name={"campaign[editions][#{locale}][subject]"}
                  value={@payload["editions"][locale]["subject"]}
                  label={gettext("Letter subject")}
                  id={"mp-template-#{locale}-subject"}
                  maxlength="200"
                />
                <p class="text-sm">
                  {gettext(
                    "Available variables: {{mp_name}}, {{district}}, {{sender_name}}, {{postal_code}}."
                  )}
                </p>
                <.live_component
                  module={PhoenixMarkdownEditor.Component}
                  id={"mp-template-#{locale}-body"}
                  source={@payload["editions"][locale]["body"]}
                  name={"campaign[editions][#{locale}][body]"}
                  label={gettext("Letter body · Markdown")}
                  preview_label={gettext("Preview ↗")}
                  preview_title={gettext("Campaign letter preview")}
                  render_preview={
                    fn source ->
                      if MPTemplates.permitted?(@current_scope),
                        do: PauseAiCa.Mail.Render.html(source),
                        else: ""
                    end
                  }
                  popup_blocked_message={gettext("Allow the preview window, then try again.")}
                  preview_open_message={gettext("Preview opened")}
                  preview_updated_message={gettext("Preview updated")}
                  disconnected_message={
                    gettext("Connection interrupted; text retained in this page.")
                  }
                  preview_error_message={gettext("Preview unavailable. Your text is retained.")}
                />
              </fieldset>
              <button type="submit" class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext(
                "Save draft"
              )}</button>
            </fieldset>
          </.form>
          <.form for={to_form(%{})} id="mp-template-publish" phx-submit="publish" class="space-y-3">
            <.input
              type="checkbox"
              id="mp-template-author-permission"
              name="author_permission"
              value="true"
              checked={false}
              label={gettext("I have the author's permission to publish this template.")}
            />
            <button
              type="submit"
              class="crm-button"
              disabled={@dirty or !connected?(@socket)}
              phx-disable-with={gettext("Publishing…")}
            >{gettext("Publish campaign template")}</button>
          </.form>
          <div :if={@template.published_revision} class="space-y-2">
            <.link
              :for={locale <- ["en", "fr"]}
              id={"mp-template-published-#{locale}"}
              href={MPTemplates.share_path(@template.slug, locale, @template.published_revision)}
              class="block underline"
            >{gettext("Published template")} · {locale} · {@template.published_revision}</.link>
          </div>
          <details id="mp-template-history">
            <summary>{gettext("Revision history")}</summary><ul class="space-y-2 break-words">
              <li :for={revision <- @history}>
                {revision.revision} · {revision_action(revision.action)} · {revision.editor_id} · {revision.inserted_at}
              </li>
            </ul>
          </details>
        </section>
      </section>
    </Layouts.management>
    """
  end
end
