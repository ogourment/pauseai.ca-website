if Code.ensure_loaded?(PhoenixCMSWeb) do
  defmodule PauseAiCaWeb.ChapterPagesLive do
    use PauseAiCaWeb, :live_view
    use PhoenixCMSWeb
    alias PauseAiCa.Incubators
    alias PauseAiCa.Incubators.ChapterMarkdown
    alias PauseAiCaWeb.{ChapterLive, ChapterPageCopy, IncubatorsLive, Site, TorontoChapterActions}
    alias PhoenixCMS.{ContentType, Website}

    @impl true
    def mount(params, _, socket) do
      locale = Site.locale(params, socket)
      Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
      socket = assign(socket, :locale, locale)

      cond do
        !available?() ->
          raise Ecto.NoResultsError, queryable: PauseAiCa.Incubators.ChapterPage

        !Application.get_env(:pauseai_ca, :incubators_enabled, false) ->
          {:ok, redirect(socket, to: IncubatorsLive.directory(locale))}

        socket.assigns.live_action == :show and params["slug"] == "toronto" and
            params["page"] == "donate" ->
          {:ok, redirect(socket, to: PauseAiCaWeb.TorontoPresentation.donate_path(locale))}

        socket.assigns.live_action == :show ->
          chapter = Incubators.published_chapter!(params["slug"])
          rows = public_rows(chapter, locale)

          with {:ok, page} <- Website.fetch(rows, chapter.group_id, params["page"]),
               false <- page.slug == "home" do
            {:ok, assign(socket, chapter: chapter, page: page, page_title: page.title)}
          else
            _ -> raise Ecto.NoResultsError, queryable: PauseAiCa.Incubators.ChapterPage
          end

        true ->
          mount_manager(socket, params)
      end
    end

    defp mount_manager(socket, params) do
      case Incubators.chapter_pages(socket.assigns.current_scope, params["id"]) do
        {:ok, profile, pages} ->
          socket = assign(socket, profile: profile, pages: pages)
          page = Enum.find(pages, &(&1.slug == params["page"]))

          case socket.assigns.live_action do
            :index ->
              {:ok, assign(socket, page_title: ChapterPageCopy.text(:chapter_pages))}

            :new ->
              {:ok, assign_editor(socket, nil)}

            :edit when not is_nil(page) ->
              {:ok, assign_editor(socket, page)}

            :preview when not is_nil(page) ->
              {:ok, assign(socket, page: page, page_title: page.draft["title"])}

            _ ->
              raise Ecto.NoResultsError, queryable: PauseAiCa.Incubators.ChapterPage
          end

        _ ->
          {:ok, redirect(socket, to: ~p"/manage/groups")}
      end
    end

    defp assign_editor(socket, page) do
      assign(socket,
        page: page,
        page_title: if(page, do: page.draft["title"], else: ChapterPageCopy.text(:add_page)),
        type: page_type(is_nil(page)),
        values: if(page, do: page.draft, else: %{}),
        errors: %{},
        status: nil
      )
    end

    defp page_type(new?) do
      slug = %{name: :slug, label: ChapterPageCopy.text(:slug), type: :string, required: true}

      ContentType.new(
        :chapter_page,
        [
          %{name: :title, label: gettext("Title"), type: :string, required: true},
          %{
            name: :navigation_order,
            label: ChapterPageCopy.text(:order),
            type: :integer,
            default: nil
          }
        ] ++
          if(new?, do: [slug], else: []) ++
          [%{name: :body, label: ChapterPageCopy.text(:body), type: :markdown, group: :content}]
      )
    end

    @impl true
    def handle_event("edit-page", %{"content" => values}, socket) do
      {:noreply, assign(socket, values: values, status: nil)}
    end

    def handle_event("save-page", %{"content" => submitted, "revision" => raw_revision}, socket) do
      %{page: page, current_scope: scope, profile: profile, type: type} = socket.assigns

      result =
        with {revision, ""} <- Integer.parse(raw_revision),
             {:ok, attrs} <- cast_page(type, submitted) do
          Incubators.save_chapter_page(
            scope,
            profile.group_id,
            page && page.slug,
            revision,
            attrs
          )
        else
          {:error, _} = error -> error
          _ -> {:error, :stale}
        end

      case result do
        {:ok, saved} when is_nil(page) ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Draft saved"))
           |> push_navigate(to: edit_path(profile, saved, socket.assigns.locale))}

        {:ok, saved} ->
          {:noreply,
           socket
           |> assign_editor(saved)
           |> assign(:status, gettext("Draft saved"))
           |> push_event("pcms:saved", %{id: "chapter-page-form"})}

        {:error, reason} ->
          {:noreply, mutation_error(assign(socket, :values, submitted), reason)}
      end
    end

    def handle_event(
          "publish-page",
          _,
          %{assigns: %{live_action: :edit, page: page, current_scope: scope, profile: profile}} =
            socket
        ) do
      case Incubators.publish_chapter_page(scope, profile.group_id, page.slug, page.revision) do
        {:ok, published} ->
          {:noreply, assign(socket, page: published, errors: %{}, status: gettext("Published"))}

        {:error, reason} ->
          {:noreply, mutation_error(socket, reason)}
      end
    end

    def handle_event(_, _, socket), do: {:noreply, socket}

    defp cast_page(type, submitted) do
      case ContentType.cast(type, submitted) do
        {:ok, attrs} -> {:ok, attrs}
        {:error, _, errors} -> {:error, {:invalid, errors}}
      end
    end

    defp mutation_error(socket, :forbidden), do: redirect(socket, to: ~p"/manage/groups")
    defp mutation_error(socket, :not_found), do: redirect(socket, to: ~p"/manage/groups")

    defp mutation_error(socket, {:invalid, errors}) do
      assign(socket,
        errors: Map.new(errors, fn {key, value} -> {key, error_text(value)} end),
        status: nil
      )
    end

    defp mutation_error(socket, reason) do
      message =
        if reason == :stale,
          do: ChapterPageCopy.text(:stale),
          else: ChapterPageCopy.text(:save_failed)

      socket
      |> put_flash(:error, message)
      |> push_event("pcms:failed", %{id: "chapter-page-form"})
    end

    defp error_text(:bad_address),
      do: ChapterPageCopy.text(:bad_address)

    defp error_text(:address_taken), do: ChapterPageCopy.text(:address_taken)
    defp error_text(:bad_title), do: ChapterPageCopy.text(:bad_title)
    defp error_text(:bad_body), do: ChapterPageCopy.text(:bad_body)
    defp error_text(:bad_order), do: ChapterPageCopy.text(:bad_order)
    defp error_text(:empty_publication), do: ChapterPageCopy.text(:publish_empty)
    defp error_text(error), do: error

    @impl true
    def render(%{live_action: :show} = assigns) do
      ~H"""
      <Layouts.app
        current_scope={@current_scope}
        flash={@flash}
        locale={@locale}
        translated_path={public_path(@chapter, @page.slug, other_locale(@locale))}
      >
        <section data-published-chapter-page class="mx-auto max-w-6xl space-y-5 px-4 py-8">
          <.link href={IncubatorsLive.directory(@locale)} class="underline">{gettext("Local groups")}</.link>
          <.navigation chapter={@chapter} locale={@locale} current={@page.slug} />
          <.website_page
            id="published-chapter-page"
            title={@page.title}
            back={public_path(@chapter, "home", @locale)}
            show_back={false}
          >
            <div lang="en">
              <TorontoChapterActions.riding_tool :if={
                @chapter.slug == "toronto" and @page.slug == "write-to-your-mp"
              } />
              <.page_body
                content={@page.body}
                chapter={@chapter.slug}
                page={@page.slug}
                locale={@locale}
              />
            </div>
          </.website_page>
        </section>
      </Layouts.app>
      """
    end

    def render(assigns) do
      ~H"""
      <Layouts.management
        current_scope={@current_scope}
        flash={@flash}
        locale={@locale}
        active_tab="group-websites"
      >
        <section class="mx-auto max-w-4xl space-y-5 px-5 py-8">
          <.link href={index_path(@profile, @locale)} class="underline">{ChapterPageCopy.text(
            :chapter_pages
          )}</.link>
          <%= case @live_action do %>
            <% :index -> %>
              <h1 class="text-3xl font-bold">{profile_name(@profile, @locale)}</h1>
              <.link
                href={~p"/manage/groups/#{@profile.group_id}/homepage?#{[locale: @locale]}"}
                class="underline"
              >
                {gettext("Edit chapter homepage")}
              </.link>
              <.collection
                id="chapter-pages"
                title={ChapterPageCopy.text(:chapter_pages)}
                rows={page_rows(@profile, @pages, @locale)}
                columns={[:title, :status]}
                new={%{href: ~p"/manage/groups/#{@profile.group_id}/new-page?#{[locale: @locale]}"}}
                labels={%{new_document: ChapterPageCopy.text(:add_page)}}
                locale={editor_locale(@locale)}
              />
            <% :preview -> %>
              <p>{ChapterPageCopy.text(:preview_label)}</p>
              <.website_page
                id="private-chapter-preview"
                title={@page.draft["title"]}
                back={edit_path(@profile, @page, @locale)}
                back_label={ChapterPageCopy.text(:back_editor)}
              >
                <div lang="en">
                  <.page_body
                    content={@page.draft["body"]}
                    chapter={@profile.chapter_slug}
                    locale={@locale}
                    page={@page.slug}
                  />
                </div>
              </.website_page>
            <% _ -> %>
              <h1 class="text-3xl font-bold">{@page_title}</h1>
              <p>{ChapterPageCopy.text(:draft_help)}</p>
              <details>
                <summary class="cursor-pointer underline">{gettext("Markdown guide")}</summary>
                <pre class="mt-2 whitespace-pre-wrap"><code>{gettext("## Next meetup\n\nJoin **local volunteers**.\n\n- Bring a friend\n- [Find an event](https://pauseai.ca/en/groups)")}</code></pre>
              </details>
              <div data-chapter-editor class="space-y-4">
                <.content_form
                  id="chapter-page"
                  type={@type}
                  values={@values}
                  errors={@errors}
                  revision={if @page, do: @page.revision, else: 0}
                  markdown_field="body"
                  labels={%{save: gettext("Save draft")}}
                  submit={%{event: "save-page"}}
                  change="edit-page"
                  locale={editor_locale(@locale)}
                  recovery_key={"chapter-page:#{@current_scope.user.id}:#{@profile.group_id}:#{if @page, do: @page.slug, else: "new"}"}
                  phx-hook="PhoenixCMSWeb"
                />
                <ChapterLive.image_library />
              </div>
              <div :if={@page} class="flex flex-wrap items-center gap-4">
                <.link
                  href={
                    ~p"/manage/groups/#{@profile.group_id}/pages/#{@page.slug}/preview?#{[locale: @locale]}"
                  }
                  class="underline"
                  target="_blank"
                  rel="noopener"
                >
                  {ChapterPageCopy.text(:preview_link)} <span aria-hidden="true">↗</span>
                </.link>
                <button
                  id="publish-chapter-page"
                  class="btn btn-primary"
                  type="button"
                  phx-click="publish-page"
                >
                  {gettext("Publish saved draft")}
                </button>
              </div>
              <p id="chapter-page-status" role="status">{@status}</p>
          <% end %>
        </section>
      </Layouts.management>
      """
    end

    defp page_body(%{chapter: "toronto", page: "plan"} = assigns) do
      assigns = assign(assigns, sections: ChapterMarkdown.toronto_plan_sections(assigns.content))

      ~H"""
      <%= for section <- @sections do %>
        <span :if={section.alias} id={section.alias} class="chapter-fragment-alias" aria-hidden="true"></span>
        {raw(PauseAiCaWeb.TorontoPresentation.national_donations(section.html, @locale))}
      <% end %>
      """
    end

    defp page_body(%{chapter: "toronto", page: "governance"} = assigns) do
      ~H"""
      {raw(
        PauseAiCaWeb.TorontoPresentation.governance(@content)
        |> PauseAiCaWeb.TorontoPresentation.national_donations(@locale)
      )}
      """
    end

    defp page_body(assigns) do
      ~H"""
      {raw(render_page(@content, @chapter, @locale))}
      """
    end

    defp render_page(content, chapter, locale) do
      html = ChapterMarkdown.render_page(content, chapter)

      if chapter == "toronto",
        do: PauseAiCaWeb.TorontoPresentation.national_donations(html, locale),
        else: html
    end

    def navigation(assigns) do
      assigns = assign_new(assigns, :current, fn -> "home" end)
      rows = public_rows(assigns.chapter, assigns.locale)
      children = Website.navigation(rows, assigns.chapter.group_id, "home")

      links =
        for page <- [hd(rows) | children] do
          %{
            title:
              if(assigns.chapter.slug == "toronto" and page.slug == "donate",
                do: gettext("Donate"),
                else: page.title
              ),
            href: public_path(assigns.chapter, page.slug, assigns.locale),
            current: page.slug == assigns.current
          }
        end

      assigns = assign(assigns, links: links, show?: children != [])

      ~H"""
      <.website_navigation
        :if={@show?}
        id="chapter-page-navigation"
        links={@links}
        label={ChapterPageCopy.text(:chapter_pages)}
        site_name={profile_name(@chapter, @locale)}
      />
      """
    end

    def manage_link(assigns) do
      ~H"""
      <.link :if={@profile.chapter_content} href={index_path(@profile, @locale)} class="underline">
        {ChapterPageCopy.text(:manage_pages)}
      </.link>
      """
    end

    defp public_rows(chapter, _locale) do
      landing = %{
        site_id: chapter.group_id,
        slug: "home",
        title: gettext("Home"),
        published?: true
      }

      children =
        for {slug, page} <- Incubators.published_chapter_pages(chapter.group_id) do
          %{
            site_id: chapter.group_id,
            slug: slug,
            title: page["title"],
            body: page["body"],
            navigation_order: page["navigation_order"],
            parent_slug: "home",
            published?: true
          }
        end

      [landing | children]
    end

    defp public_path(%{slug: "toronto"}, "donate", locale),
      do: PauseAiCaWeb.TorontoPresentation.donate_path(locale)

    defp public_path(chapter, "home", locale), do: ~p"/groups/#{chapter.slug}?#{[locale: locale]}"

    defp public_path(chapter, slug, locale),
      do: ~p"/groups/#{chapter.slug}/pages/#{slug}?#{[locale: locale]}"

    defp index_path(profile, locale),
      do: ~p"/manage/groups/#{profile.group_id}/pages?#{[locale: locale]}"

    defp edit_path(profile, page, locale),
      do: ~p"/manage/groups/#{profile.group_id}/pages/#{page.slug}?#{[locale: locale]}"

    defp page_rows(profile, pages, locale) do
      for page <- pages do
        %{
          id: page.id,
          title: page.draft["title"],
          status: if(page.published, do: "published", else: "draft"),
          open: %{href: edit_path(profile, page, locale)}
        }
      end
    end

    defp profile_name(profile, "fr"), do: profile.name_fr
    defp profile_name(profile, _), do: profile.name_en
    defp other_locale("fr"), do: "en"
    defp other_locale(_), do: "fr"
    defp editor_locale("fr"), do: :fr
    defp editor_locale(_), do: :en
    def available?, do: Application.get_env(:pauseai_ca, :chapter_pages_enabled, false)
  end
else
  defmodule PauseAiCaWeb.ChapterPagesLive do
    use Phoenix.Component

    def available?, do: not is_nil(Application.spec(:phoenix_cms_web, :vsn))
    def navigation(assigns), do: ~H""
    def manage_link(assigns), do: ~H""
  end
end
