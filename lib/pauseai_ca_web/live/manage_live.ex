defmodule PauseAiCaWeb.ManageLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCaWeb.Navigation

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    sections =
      socket.assigns.current_scope |> Navigation.assemble(locale) |> Navigation.manage_sections()

    if sections == [] do
      {:ok, redirect(socket, to: ~p"/dashboard")}
    else
      stats =
        if Enum.any?(sections, fn section ->
             Enum.any?(section.items, &(&1.id == "pauseai.groups"))
           end) do
          PauseAiCa.Incubators.manage_overview(socket.assigns.current_scope, connected?(socket))
        end

      {:ok,
       assign(socket,
         locale: locale,
         sections: sections,
         stats: stats,
         page_title: gettext("Manage")
       )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_scope={@current_scope}
      locale={@locale}
      flash={@flash}
      show_announcements={false}
    >
      <section class="mx-auto max-w-6xl px-5 py-8" data-journey-start>
        <h1 class="mb-6 text-3xl font-bold">{gettext("Manage")}</h1>
        <section :if={@stats} id="group-snapshot" class="mb-6 rounded-lg border border-stone-300 p-5">
          <h2 class="mb-2 text-xl font-semibold">{gettext("Your groups")}</h2>
          <p>
            {ngettext("%{count} group", "%{count} groups", @stats.groups)} ·
            <.link class="underline" href={~p"/manage/groups?#{[locale: @locale]}"}>{ngettext(
              "%{count} pending membership request",
              "%{count} pending membership requests",
              @stats.pending
            )}</.link>
          </p>
          <p :if={@stats.changes != nil}>
            {ngettext(
              "%{count} group activity entry since your last Manage visit",
              "%{count} group activity entries since your last Manage visit",
              Enum.sum(Enum.map(@stats.changes, & &1.count))
            )}
          </p>
          <ul :if={@stats.changes not in [nil, []]} class="mt-2">
            <li :for={group <- @stats.changes}>
              <.link
                class="underline"
                href={~p"/manage/groups?#{[group: group.id, tab: "activity", locale: @locale]}"}
              >{group.name} ({group.count})</.link>
            </li>
          </ul>
          <p :if={@stats.changes == nil}>
            {gettext("Your next visit will show new group activity here.")}
          </p>
        </section>
        <div class="grid gap-5 sm:grid-cols-2">
          <section
            :for={section <- @sections}
            id={section.key}
            class="rounded-lg border border-stone-300 p-5"
          >
            <h2 class="mb-3 text-xl font-semibold">{section.label}</h2>
            <ul class="space-y-2">
              <li :for={item <- section.items}>
                <.link class="underline" href={item.href}>{item.label}</.link>
              </li>
            </ul>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
