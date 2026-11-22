defmodule PauseAiCaWeb.ChapterLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Incubators
  alias PauseAiCa.Incubators.ChapterMarkdown
  alias PauseAiCaWeb.IncubatorsLive

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    socket = assign(socket, locale: locale, page_title: gettext("Chapter homepage"))

    cond do
      not Application.get_env(:pauseai_ca, :incubators_enabled, false) ->
        {:ok, redirect(socket, to: IncubatorsLive.directory(locale))}

      socket.assigns.live_action == :index ->
        scope = socket.assigns.current_scope

        if PauseAiCa.Volunteers.allowed?(scope) do
          groups = Incubators.managed_groups(scope)
          ids = MapSet.new(groups, & &1.id)
          chapters = Enum.filter(Incubators.public_groups(), &MapSet.member?(ids, &1.group_id))
          {:ok, assign(socket, chapters: chapters, page_title: gettext("Group websites"))}
        else
          {:ok, redirect(socket, to: ~p"/dashboard")}
        end

      socket.assigns.live_action == :show ->
        chapter = Incubators.published_chapter!(params["slug"])
        {:ok, assign(socket, chapter: chapter, path: "/groups/#{chapter.slug}")}

      true ->
        case Incubators.configuration(socket.assigns.current_scope, params["id"]) do
          {:ok, %{published: true} = profile} ->
            {:ok,
             socket
             |> assign(path: "/manage/groups/#{profile.group_id}/homepage")
             |> load(profile)}

          _ ->
            {:ok, redirect(socket, to: "/manage/groups")}
        end
    end
  end

  defp load(socket, profile) do
    fields = Map.put(profile.chapter_draft, "slug", profile.chapter_slug)
    assign(socket, profile: profile, form: to_form(fields, as: :chapter))
  end

  @impl true
  def handle_info({:markdown_editor_changed, "chapter-editor-" <> lang, source}, socket)
      when lang in ~w(en fr) do
    {:noreply,
     update(socket, :form, fn form ->
       to_form(Map.put(form.params, lang, source), as: :chapter)
     end)}
  end

  @impl true
  def handle_event("save", %{"chapter" => fields}, socket) do
    %{profile: p, current_scope: scope} = socket.assigns
    socket = assign(socket, form: to_form(fields, as: :chapter))

    result(
      socket,
      Incubators.save_chapter(scope, p.group_id, p.revision, fields),
      gettext("Draft saved")
    )
  end

  def handle_event("publish", _, socket) do
    %{profile: p, current_scope: scope} = socket.assigns

    result(
      socket,
      Incubators.publish_chapter(scope, p.group_id, p.revision),
      gettext("Published")
    )
  end

  defp result(socket, {:ok, p}, notice),
    do: {:noreply, socket |> load(p) |> put_flash(:info, notice)}

  defp result(socket, {:error, :forbidden}, _),
    do: {:noreply, redirect(socket, to: "/manage/groups")}

  defp result(socket, {:error, reason}, _) do
    message =
      case reason do
        :stale ->
          gettext("The group changed. Reload before editing again.")

        :incomplete ->
          gettext("Save a welcome before publishing.")

        _ ->
          gettext("Check the chapter address and welcome text. Your changes have not been saved.")
      end

    {:noreply, put_flash(socket, :error, message)}
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.management
      current_scope={@current_scope}
      flash={@flash}
      locale={@locale}
      active_tab="group-websites"
    >
      <section class="mx-auto max-w-4xl px-5 py-8">
        <h1 class="mb-5 text-3xl font-bold">{gettext("Group websites")}</h1>
        <p :if={@chapters == []}>
          {gettext("None of the groups you manage is published in the local directory.")}
        </p>
        <ul class="divide-y divide-stone-200">
          <li
            :for={chapter <- @chapters}
            class="flex flex-wrap items-center justify-between gap-3 py-4"
          >
            <strong>{if @locale == "fr", do: chapter.name_fr, else: chapter.name_en}</strong>
            <.link
              class="underline"
              href={~p"/manage/groups/#{chapter.group_id}/homepage?#{[locale: @locale]}"}
            >{gettext("Edit chapter homepage")}<span class="sr-only"> · {if @locale == "fr",
              do: chapter.name_fr,
              else: chapter.name_en}</span></.link>
          </li>
        </ul>
      </section>
    </Layouts.management>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      locale={@locale}
      current_scope={@current_scope}
      active_tab={if @live_action == :edit, do: "group-websites"}
      translated_path={@path <> "?locale=" <> if(@locale == "fr", do: "en", else: "fr")}
    >
      <section class={[
        "mx-auto space-y-5 px-4 py-8",
        if(@live_action == :show, do: "max-w-6xl", else: "max-w-4xl")
      ]}>
        <.link href={IncubatorsLive.directory(@locale)} class="underline">{gettext("Local groups")}</.link>
        <%= if @live_action == :show do %>
          <div data-published-chapter>
            <.chapter_content group={@chapter} content={@chapter.content} locale={@locale} />
          </div>
        <% else %>
          <h1 class="text-3xl font-bold">{gettext("Edit chapter homepage")}</h1>
          <.form for={@form} id="chapter-form" phx-submit="save" class="space-y-4">
            <.input
              field={@form[:slug]}
              label={gettext("Chapter address under /groups/")}
              readonly={!!@profile.chapter_slug}
              required
            />
            <details>
              <summary class="cursor-pointer underline">{gettext("Markdown guide")}</summary>
              <pre class="mt-2 whitespace-pre-wrap"><code>{gettext("## Next meetup\n\nJoin **local volunteers**.\n\n- Bring a friend\n- [Find an event](https://pauseai.ca/en/groups)")}</code></pre>
            </details>
            <.edition lang="en" form={@form} profile={@profile} />
            <details open={String.trim(@profile.chapter_draft["fr"] || "") != "" || @locale == "fr"}>
              <summary class="cursor-pointer underline">
                {gettext("French edition (optional)")}
              </summary>
              <.edition lang="fr" form={@form} profile={@profile} />
            </details>
            <button class="btn">{gettext("Save draft")}</button>
          </.form>
          <div :if={@profile.chapter_draft != %{}} class="border-t pt-4">
            <button type="button" id="chapter-publish" class="btn btn-primary" phx-click="publish">{gettext(
              "Publish saved draft"
            )}</button>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp edition(assigns) do
    ~H"""
    <div class="space-y-2" id={"chapter-edition-#{@lang}"}>
      <.live_component
        module={PhoenixMarkdownEditor.Component}
        id={"chapter-editor-#{@lang}"}
        source={@form.params[@lang] || ""}
        name={"chapter[#{@lang}]"}
        label={if @lang == "en", do: gettext("English welcome"), else: gettext("French welcome")}
        render_preview={fn source -> preview(@profile, @lang, source) end}
        preview_label={gettext("Preview") <> " ↗"}
        preview_title={gettext("Draft preview")}
        popup_blocked_message={gettext("Allow the preview window, then try again.")}
        preview_open_message={gettext("Preview opened")}
        preview_updated_message={gettext("Preview updated")}
        preview_error_message={gettext("Preview unavailable. Your text is retained.")}
        disconnected_message={gettext("Connection interrupted; text retained in this page.")}
      />
      <details>
        <summary class="cursor-pointer underline">{gettext("Image library")}</summary>
        <div class="grid gap-3 sm:grid-cols-2">
          <button
            :for={{url, alt, credit} <- ChapterMarkdown.images()}
            type="button"
            data-snippet={"\n\n![#{alt}](#{url})\n\n*#{credit}*\n"}
            phx-click={JS.dispatch("chapter:insert-image")}
            class="text-left rounded border p-2"
          >
            <img src={url} alt={alt} loading="lazy" class="h-24 w-full object-cover" />
            <span>{gettext("Insert image")} · {credit}</span>
          </button>
        </div>
      </details>
    </div>
    """
  end

  defp preview(group, locale, source) do
    chapter_content(%{
      __changed__: nil,
      group: group,
      content: %{locale => source},
      locale: locale
    })
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp chapter_content(assigns) do
    lang =
      if String.trim(assigns.content[assigns.locale] || "") != "",
        do: assigns.locale,
        else: if(assigns.locale == "en", do: "fr", else: "en")

    assigns =
      assign(assigns,
        content_lang: lang,
        welcome: ChapterMarkdown.render(assigns.content[lang] || "")
      )

    ~H"""
    <article class="space-y-6">
      <div class={["grid items-start gap-6", @welcome.photo != "" && "md:grid-cols-2 md:gap-10"]}>
        <div class="min-w-0 space-y-4">
          <h1 class="text-4xl font-bold">
            {if @locale == "fr", do: @group.name_fr, else: @group.name_en}
          </h1>
          <p>{gettext("A local chapter of PauseAI Canada.")}</p>
          <.welcome_text html={@welcome.intro} lang={@content_lang} />
          <div class="flex flex-wrap items-center gap-4">
            <.link
              href={IncubatorsLive.directory(@locale) <> "#group-#{@group.group_id}"}
              class="btn btn-primary"
            >{gettext("Get involved")}</.link>
            <.link :if={@group.events_url} href={@group.events_url} class="underline">{gettext(
              "Events"
            )}</.link>
          </div>
        </div>
        <figure
          :if={@welcome.photo != ""}
          lang={@content_lang}
          class="min-w-0 [&_img]:w-full [&_img]:h-auto [&_img]:rounded-xl"
        >
          {raw(@welcome.photo)}
          <figcaption :if={@welcome.caption != ""} class="mt-2 text-sm">
            {raw(@welcome.caption)}
          </figcaption>
        </figure>
      </div>
      <.welcome_text html={@welcome.body} lang={@content_lang} />
    </article>
    """
  end

  defp welcome_text(assigns) do
    ~H"""
    <div
      :if={@html != ""}
      lang={@lang}
      class="max-w-prose space-y-3 leading-relaxed [&_h2]:text-2xl [&_h3]:text-xl [&_a]:underline [&_ul]:list-disc [&_ol]:list-decimal [&_ul]:pl-6 [&_ol]:pl-6 [&_img]:rounded-xl"
    >
      {raw(@html)}
    </div>
    """
  end
end
