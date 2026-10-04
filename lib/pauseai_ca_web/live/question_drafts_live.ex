defmodule PauseAiCaWeb.QuestionDraftsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Volunteers, Learning.QuestionBank}
  alias PauseAiCa.Mail.Render

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.allowed?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Quiz drafts"),
         draft: nil,
         records: [],
         form: to_form(%{}, as: "question"),
         status: nil,
         error: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Organizer access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  def handle_params(params, _, socket) do
    if id = params["id"] do
      case QuestionBank.get(socket.assigns.current_scope, id) do
        {:ok, draft} ->
          {:noreply, load(socket, draft)}

        _ ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("Draft unavailable."))
           |> push_navigate(to: ~p"/manage/questions")}
      end
    else
      {:noreply,
       assign(socket, records: QuestionBank.list(socket.assigns.current_scope), draft: nil)}
    end
  end

  def handle_event("new", _, socket) do
    case QuestionBank.create(socket.assigns.current_scope) do
      {:ok, draft} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/manage/questions/#{draft.id}?locale=#{socket.assigns.locale}"
         )}

      _ ->
        {:noreply, assign(socket, error: gettext("Could not save. Your changes are retained."))}
    end
  end

  def handle_event("edit", %{"question" => values}, socket), do: {:noreply, save(socket, values)}
  def handle_event("save", %{"question" => values}, socket), do: {:noreply, save(socket, values)}

  def handle_event("reload", _, socket) do
    {:ok, draft} = QuestionBank.get(socket.assigns.current_scope, socket.assigns.draft.id)
    {:noreply, load(socket, draft)}
  end

  def handle_info({:markdown_editor_changed, "question-explanation", source}, socket) do
    values = Map.put(socket.assigns.form.params, "answer", source)
    {:noreply, save(socket, values)}
  end

  defp save(socket, values) do
    values = Map.merge(socket.assigns.form.params, values)
    socket = assign(socket, form: to_form(values, as: "question"))

    case QuestionBank.save(
           socket.assigns.current_scope,
           socket.assigns.draft,
           socket.assigns.locale,
           values
         ) do
      {:ok, draft} ->
        assign(socket, draft: draft, status: gettext("Saved"), error: nil)

      {:error, :stale} ->
        assign(socket,
          status: gettext("Unsaved changes"),
          error:
            gettext(
              "Another reviewer saved changes. Copy your edits before reloading their version."
            )
        )

      _ ->
        assign(socket,
          status: gettext("Unsaved changes"),
          error:
            gettext(
              "Check the URLs, answer choices and correct answer. Your changes are retained."
            )
        )
    end
  end

  defp load(socket, draft),
    do:
      assign(socket,
        draft: draft,
        form: to_form(QuestionBank.values(draft, socket.assigns.locale), as: "question"),
        status: gettext("Saved"),
        error: nil
      )

  def render(assigns) do
    ~H"""
    <Layouts.management
      active_tab="questions"
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
    >
      <main class="mx-auto max-w-5xl px-5 py-10 crm-surface">
        <h1 class="text-3xl font-bold">{gettext("Quiz drafts")}</h1>
        <p class="my-3">
          {gettext(
            "Organizers share these drafts. Changes are saved automatically; drafts stay out of the public quiz."
          )}
        </p>
        <p :if={@error} role="alert" class="my-4 rounded-lg border border-red-700 p-4 text-red-800">
          {@error}
        </p>
        <div :if={!@draft}>
          <button id="question-new" phx-click="new" class="crm-button my-4">{gettext("New question")}</button>
          <ul id="question-drafts" class="divide-y divide-stone-200">
            <li :for={q <- @records} class="py-4">
              <.link
                navigate={~p"/manage/questions/#{q.id}?locale=#{@locale}"}
                class="font-semibold underline"
              >{q.review_id} · {get_in(q.editions, [@locale, "question"]) || gettext("Untitled draft")}</.link>
              <p class="mt-1 text-sm">
                {gettext("Draft")} · {q.kind} · {gettext("Revision")} {q.revision}
              </p>
            </li>
          </ul>
        </div>
        <div :if={@draft}>
          <div class="my-5 flex flex-wrap gap-5">
            <.link navigate={~p"/manage/questions?locale=#{@locale}"} class="underline">{gettext(
              "All drafts"
            )}</.link>
            <.link href={~p"/manage/questions/#{@draft.id}?locale=en"} hreflang="en" class="underline">English</.link>
            <.link href={~p"/manage/questions/#{@draft.id}?locale=fr"} hreflang="fr" class="underline">Français</.link>
          </div>
          <h2 class="text-xl font-bold">{@draft.review_id}</h2>
          <p class="my-2">
            {gettext("Draft")} · {gettext("Revision")} {@draft.revision} ·
            <span id="question-save-status" role="status">{@status}</span>
          </p>
          <button :if={@error} phx-click="reload" class="crm-button my-3">{gettext(
            "Reload saved version"
          )}</button>
          <.form
            for={@form}
            id="question-draft-form"
            phx-change="edit"
            phx-submit="save"
            class="space-y-5"
            phx-debounce="400"
          >
            <.input
              phx-debounce="400"
              field={@form[:question]}
              type="textarea"
              label={gettext("Question")}
            />
            <div class="grid gap-5 md:grid-cols-2">
              <.input
                field={@form[:kind]}
                type="select"
                label={gettext("Question format")}
                options={[
                  {gettext("Scored question"), "factual"},
                  {gettext("Opinion"), "opinion"},
                  {gettext("Action planning"), "planning"},
                  {gettext("Discussion"), "discussion"}
                ]}
              />
              <.input phx-debounce="400" field={@form[:topic]} label={gettext("Topic")} />
            </div>
            <.input
              field={@form[:options]}
              type="textarea"
              label={gettext("Answer choices · one per line")}
            />
            <.input
              field={@form[:correct]}
              type="select"
              label={gettext("Correct answer")}
              options={
                [{gettext("Ungraded / not decided"), ""}] ++
                  Enum.map(0..11, &{to_string(&1 + 1), to_string(&1)})
              }
            />
            <.live_component
              module={PhoenixMarkdownEditor.Component}
              id="question-explanation"
              source={@form[:answer].value || ""}
              name="question[answer]"
              label={gettext("Explanation · Markdown")}
              preview_label={gettext("Preview ↗")}
              preview_title={@form[:question].value || ""}
              render_preview={&Render.html/1}
              popup_blocked_message={gettext("Allow the preview window, then try again.")}
              preview_open_message={gettext("Preview opened")}
              preview_updated_message={gettext("Preview updated")}
              disconnected_message={gettext("Connection interrupted; text retained in this page.")}
              preview_error_message={gettext("Preview unavailable. Your text is retained.")}
            />
            <.input phx-debounce="400" field={@form[:source]} label={gettext("Source name")} />
            <.input phx-debounce="400" field={@form[:url]} type="url" label={gettext("Source URL")} />
            <.input
              phx-debounce="400"
              field={@form[:action]}
              type="textarea"
              label={gettext("Next action")}
            />
            <details class="rounded-lg border border-stone-300 p-4">
              <summary class="cursor-pointer font-semibold">
                {gettext("Image and source assessment")}
              </summary>
              <div class="mt-4 space-y-4">
                <.input
                  phx-debounce="400"
                  field={@form[:image_url]}
                  label={gettext("Optional image URL")}
                />
                <.input
                  phx-debounce="400"
                  field={@form[:image_alt]}
                  label={gettext("Image description")}
                />
                <.input
                  phx-debounce="400"
                  field={@form[:image_credit]}
                  label={gettext("Image credit / permission")}
                />
                <.input
                  field={@form[:social_proof]}
                  type="textarea"
                  label={gettext("Estimated social proof and possible bias")}
                />
              </div>
            </details>
            <.input
              phx-debounce="400"
              field={@form[:notes]}
              type="textarea"
              label={gettext("Reviewer notes")}
            />
            <button class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext("Save draft")}</button>
          </.form>
          <section
            class="mt-8 rounded-xl border border-stone-300 p-5"
            aria-label={gettext("Question preview")}
          >
            <h2 class="text-xl font-bold">{gettext("Question preview")}</h2>
            <img
              :if={@form[:image_url].value not in [nil, ""] and !@error}
              src={@form[:image_url].value}
              alt={@form[:image_alt].value || ""}
              class="my-4 max-h-64 max-w-full"
            />
            <h3 class="my-4 text-xl">{@form[:question].value}</h3>
            <ol class="list-decimal space-y-2 pl-6">
              <li :for={choice <- String.split(@form[:options].value || "", "\n", trim: true)}>
                {choice}
              </li>
            </ol>
            <div class="prose my-5">{Phoenix.HTML.raw(Render.html(@form[:answer].value || ""))}</div>
            <p :if={@form[:action].value not in [nil, ""]}>{@form[:action].value}</p>
          </section>
        </div>
      </main>
    </Layouts.management>
    """
  end
end
