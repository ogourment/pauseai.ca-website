defmodule PauseAiCaWeb.BlogEditorLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Blog
  alias PauseAiCaWeb.BlogLive

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Blog.permitted?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Blog"),
         error: nil,
         article: nil,
         history: [],
         preview: false,
         dirty: false,
         status: gettext("Saved")
       )}
    else
      {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    with {:ok, articles} <- Blog.list(socket.assigns.current_scope),
         {:ok, article} <-
           if(params["id"],
             do: Blog.get(socket.assigns.current_scope, params["id"]),
             else: {:ok, nil}
           ) do
      socket =
        assign(socket,
          articles: articles,
          article: article,
          error: if(params["id"] && is_nil(article), do: gettext("Article unavailable")),
          preview: false
        )

      {:noreply, if(article, do: load(socket, article), else: socket)}
    else
      _ -> {:noreply, redirect(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if Blog.permitted?(socket.assigns.current_scope) do
      dispatch(event, params, socket)
    else
      {:noreply,
       socket
       |> assign(article: nil, payload: %{}, preview: false)
       |> redirect(to: ~p"/dashboard")}
    end
  end

  defp dispatch(event, _, %{assigns: %{article: nil}} = socket) when event != "create",
    do: {:noreply, socket}

  defp dispatch(event, _, %{assigns: %{dirty: true}} = socket)
       when event in ["unpublish", "archive"], do: {:noreply, socket}

  defp dispatch("create", %{"article" => %{"slug" => slug}}, socket) when is_binary(slug) do
    case Blog.create(socket.assigns.current_scope, slug) do
      {:ok, article} ->
        {:noreply,
         push_navigate(socket,
           to: "/manage/blog/" <> article.id <> "?locale=" <> socket.assigns.locale
         )}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("Use a unique address with lowercase letters, numbers and hyphens.")
         )}
    end
  end

  defp dispatch("edit", %{"article" => values}, socket) when is_map(values),
    do: {:noreply, edit(socket, values)}

  defp dispatch("submit", %{"article" => values} = params, socket) when is_map(values) do
    socket = edit(socket, values)
    scope = socket.assigns.current_scope
    article = socket.assigns.article

    case params["intent"] do
      "preview" ->
        {:noreply, assign(socket, preview: true)}

      "publish" when socket.assigns.dirty ->
        {:noreply, assign(socket, error: gettext("Save your changes before publishing."))}

      "publish" ->
        result(socket, Blog.publish(scope, article))

      _ ->
        result(socket, Blog.save(scope, article, socket.assigns.payload))
    end
  end

  defp dispatch("unpublish", _, socket),
    do: result(socket, Blog.unpublish(socket.assigns.current_scope, socket.assigns.article))

  defp dispatch("archive", _, socket) do
    case Blog.archive(socket.assigns.current_scope, socket.assigns.article) do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: "/manage/blog?locale=" <> socket.assigns.locale)}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp dispatch("restore", %{"id" => id}, socket),
    do: result(socket, Blog.restore(socket.assigns.current_scope, socket.assigns.article, id))

  defp dispatch(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:markdown_editor_changed, "blog-" <> key, source}, socket) do
    if (Blog.permitted?(socket.assigns.current_scope) and socket.assigns.article) &&
         is_binary(source) do
      case String.split(key, "-", parts: 2) do
        [locale, field] when locale in ~w(en fr) and field in ~w(details full) ->
          {:noreply, edit(socket, %{locale => %{field => source}})}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply,
       socket
       |> assign(article: nil, payload: %{}, preview: false)
       |> redirect(to: ~p"/dashboard")}
    end
  end

  defp edit(socket, values) do
    payload =
      Enum.reduce(~w(en fr), socket.assigns.payload, fn locale, acc ->
        Map.update!(
          acc,
          locale,
          &Map.merge(
            &1,
            Map.take(
              if(is_map(values[locale]), do: values[locale], else: %{}),
              ~w(title summary details full)
            )
          )
        )
      end)

    payload = if Blog.validate(payload, :draft) == :ok, do: payload, else: socket.assigns.payload
    dirty = payload != socket.assigns.article.payload

    assign(socket,
      payload: payload,
      dirty: dirty,
      status: if(dirty, do: gettext("Unsaved changes"), else: gettext("Saved")),
      error: nil
    )
  end

  defp load(socket, article) do
    {:ok, history} = Blog.history(socket.assigns.current_scope, article)

    socket
    |> push_event("blog-draft-saved", %{})
    |> assign(
      article: article,
      payload: article.payload,
      history: history,
      dirty: false,
      status: gettext("Saved"),
      error: nil
    )
  end

  defp result(socket, {:ok, article}), do: {:noreply, load(socket, article)}
  defp result(socket, {:error, reason}), do: failure(socket, reason)

  defp failure(socket, :stale),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext(
             "This article changed elsewhere. Reload before saving; your text is still shown."
           )
       )}

  defp failure(socket, :invalid_content),
    do:
      {:noreply,
       assign(socket,
         error:
           gettext(
             "Complete all four fields in at least one language before publication. Titles allow 200 characters, summaries 1,000 and each detail section 100,000."
           )
       )}

  defp failure(socket, _),
    do:
      {:noreply,
       assign(socket, error: gettext("The change could not be saved. Your text is still shown."))}

  defp public_url(slug, locale, depth),
    do: PauseAiCaWeb.Endpoint.url() <> BlogLive.path(locale) <> "/" <> slug <> "?depth=" <> depth

  defp revision_action("created"), do: gettext("Created")
  defp revision_action("saved"), do: gettext("Saved")
  defp revision_action("published"), do: gettext("Published")
  defp revision_action("restored"), do: gettext("Restored to draft")
  defp revision_action("unpublished"), do: gettext("Unpublished")
  defp revision_action("archived"), do: gettext("Archived")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="blog"
    >
      <section class="mx-auto max-w-5xl space-y-6 py-8">
        <h1 class="text-3xl font-semibold">{gettext("Blog")}</h1>
        <p :if={@error} id="blog-error" role="alert" class="crm-error">{@error}</p>
        <.link :if={@article} navigate={"/manage/blog?locale=" <> @locale} class="underline">{gettext(
          "All articles"
        )}</.link>
        <section :if={is_nil(@article)} class="space-y-6">
          <.form
            for={to_form(%{}, as: "article")}
            id="blog-create"
            phx-submit="create"
            class="space-y-3"
          >
            <.input
              name="article[slug]"
              label={gettext("Article address")}
              value=""
              required
              pattern="[a-z0-9]+(-[a-z0-9]+)*"
              maxlength="100"
            />
            <p>
              {gettext(
                "The address stays the same after creation. Use lowercase letters, numbers and hyphens."
              )}
            </p>
            <button class="crm-button" type="submit">{gettext("Create article")}</button>
          </.form>
          <ul class="space-y-4">
            <li :for={article <- @articles}>
              <.link
                navigate={"/manage/blog/" <> article.id <> "?locale=" <> @locale}
                class="underline"
              >{if article.payload[@locale]["title"] == "",
                do: article.slug,
                else: article.payload[@locale]["title"]}</.link>
              · {if article.published_payload, do: gettext("Published"), else: gettext("Draft")}
            </li>
          </ul>
        </section>
        <section :if={@article} class="space-y-7">
          <p class="break-all">{BlogLive.path(@locale) <> "/" <> @article.slug}</p>
          <p>{if @article.published_payload, do: gettext("Published"), else: gettext("Draft")}</p>
          <section
            :if={@article.published_payload && @article.published_payload[@locale]}
            class="space-y-3 rounded-xl border border-stone-300 p-4"
          >
            <h2 class="text-lg font-semibold">{gettext("Article links")}</h2>
            <p>{gettext("Choose the starting level of detail when sharing this article.")}</p>
            <p :for={
              {depth, label} <- [
                {"summary", gettext("In brief")},
                {"details", gettext("More details")},
                {"full", gettext("Everything")}
              ]
            }>
              <span class="font-semibold">{label}: </span>
              <.link
                href={public_url(@article.slug, @locale, depth)}
                target="_blank"
                rel="noopener"
                class="break-all underline"
              >{public_url(@article.slug, @locale, depth)}</.link>
            </p>
          </section>
          <.form
            for={to_form(%{}, as: "article")}
            id="blog-editor"
            phx-hook=".BlogDraftGuard"
            data-dirty={to_string(@dirty)}
            data-unsaved-message={gettext("Leave this page and discard unsaved changes?")}
            phx-change="edit"
            phx-submit="submit"
            class="space-y-6"
          >
            <div class="flex flex-wrap items-center gap-3">
              <button name="intent" value="save" class="crm-button">{gettext("Save")}</button>
              <button name="intent" value="preview" class="crm-button">{gettext("Preview")}</button>
              <button
                id="blog-publish"
                name="intent"
                value="publish"
                disabled={@dirty}
                data-confirm={
                  gettext("Publish the complete language editions of this saved article?")
                }
                class="crm-button"
              >{gettext("Publish")}</button>
              <span id="blog-save-status" role="status">{@status}</span>
            </div>
            <fieldset
              :for={locale <- ~w(en fr)}
              class="space-y-4 rounded-xl border border-stone-300 p-5"
            >
              <legend class="px-2 text-xl font-semibold">
                {if locale == "en", do: "English", else: "Français"}
              </legend>
              <.input
                id={"blog-#{locale}-title"}
                name={"article[#{locale}][title]"}
                label={gettext("Title")}
                value={@payload[locale]["title"]}
                maxlength="200"
              />
              <.input
                id={"blog-#{locale}-summary"}
                name={"article[#{locale}][summary]"}
                type="textarea"
                label={gettext("Short summary")}
                value={@payload[locale]["summary"]}
                maxlength="1000"
              />
              <.live_component
                :for={
                  {field, label} <- [
                    {"details", gettext("More details")},
                    {"full", gettext("Everything")}
                  ]
                }
                module={PhoenixMarkdownEditor.Component}
                id={"blog-#{locale}-#{field}"}
                source={@payload[locale][field]}
                name={"article[#{locale}][#{field}]"}
                label={label}
                render_preview={&PauseAiCa.Mail.Render.html/1}
                preview_label={gettext("Preview ↗")}
                preview_title={gettext("Draft preview")}
                popup_blocked_message={gettext("Allow the preview window, then try again.")}
                preview_open_message={gettext("Preview opened")}
                preview_updated_message={gettext("Preview updated")}
                disconnected_message={gettext("Connection interrupted; text retained in this page.")}
                preview_error_message={gettext("Preview unavailable. Your text is retained.")}
              />
            </fieldset>
          </.form>
          <section
            :if={@preview}
            id="blog-preview"
            class="space-y-6 rounded-xl border-2 border-brand p-5"
          >
            <h2 class="text-2xl font-semibold">{gettext("Draft preview")}</h2>
            <div :for={locale <- ~w(en fr)} lang={locale}>
              <h3 class="mb-4 font-semibold">{if locale == "en", do: "English", else: "Français"}</h3><PauseAiCaWeb.BlogContent.article
                id={"blog-preview-" <> locale}
                edition={@payload[locale]}
                depth="full"
              />
            </div>
          </section>
          <div class="flex flex-wrap gap-3">
            <button
              :if={@article.published_payload}
              type="button"
              phx-click="unpublish"
              disabled={@dirty}
              data-confirm={gettext("Remove this article from the public blog?")}
              class="crm-button"
            >{gettext("Unpublish")}</button>
            <button
              type="button"
              phx-click="archive"
              disabled={@dirty}
              data-confirm={
                gettext(
                  "Archive this article and remove it from the public blog? Revision history is retained."
                )
              }
              class="crm-button"
            >{gettext("Archive")}</button>
          </div>
          <details id="blog-history" class="rounded-xl border border-stone-300 p-5">
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
                )}</span><button
                  type="button"
                  phx-click="restore"
                  phx-value-id={revision.id}
                  data-confirm={
                    gettext(
                      "Replace the current draft with this revision? Publication stays unchanged."
                    )
                  }
                  class="crm-button"
                >{gettext("Restore to draft")}</button>
              </li>
            </ol>
          </details>
        </section>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".BlogDraftGuard">
        export default {
          mounted() {
            this.localDirty = false
            this.markDirty = () => { this.localDirty = true }
            this.hasChanges = () => this.localDirty || this.el.dataset.dirty === "true"
            this.unload = event => { if (this.hasChanges()) { event.preventDefault(); event.returnValue = "" } }
            this.navigate = event => {
              const link = event.target.closest("a[href]")
              if (link && !link.hasAttribute("download") && this.hasChanges() && !window.confirm(this.el.dataset.unsavedMessage)) {
                event.preventDefault(); event.stopImmediatePropagation()
              }
            }
            this.el.addEventListener("input", this.markDirty)
            window.addEventListener("beforeunload", this.unload)
            document.addEventListener("click", this.navigate, true)
            this.handleEvent("blog-draft-saved", () => { this.localDirty = false })
          },
          destroyed() {
            this.el.removeEventListener("input", this.markDirty)
            window.removeEventListener("beforeunload", this.unload)
            document.removeEventListener("click", this.navigate, true)
          }
        }
      </script>
    </Layouts.management>
    """
  end
end
