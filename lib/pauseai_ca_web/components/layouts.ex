defmodule PauseAiCaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PauseAiCaWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :locale, :string, default: nil

  attr :translated_path, :string,
    default: nil,
    doc: "where the language switch should go; defaults to the other home page"

  attr :promote_warning_shot, :boolean,
    default: true,
    doc: "whether to show the site-wide warning-shot banner and prompt"

  attr :show_announcements, :boolean, default: true

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :locale, assigns.locale || Gettext.get_locale(PauseAiCaWeb.Gettext))

    ~H"""
    <header class="sticky top-0 z-40 border-b border-stone-200/80 bg-[#f8f5ed]/95 backdrop-blur">
      <nav
        class="mx-auto flex max-w-6xl items-center gap-2 px-3 py-4 sm:gap-5 sm:px-5"
        aria-label="Main navigation"
      >
        <a
          href={if(@locale == "fr", do: ~p"/fr", else: ~p"/en")}
          class="mr-auto flex shrink-0 items-center gap-3"
        >
          <span class="relative inline-flex">
            <img
              src={~p"/images/pauseai-canada-logo.png"}
              alt=""
              width="36"
              height="36"
              class="size-9"
            />
            <span
              :if={PauseAiCa.Environment.badged?()}
              class="pointer-events-none absolute -right-3 top-1/4 -translate-y-1/2 rotate-[-12deg] rounded-[3px] px-1.5 py-0.5 text-[10px] font-black uppercase leading-none tracking-wide text-white shadow-sm"
              style={"background: #{env_badge_colour()}"}
            >
              {PauseAiCa.Environment.label()}
            </span>
          </span>
          <span class="hidden font-semibold tracking-tight text-stone-900 sm:inline">{gettext(
            "PauseAI Canada"
          )}</span>
        </a>
        <details id="learn-menu" class="act-menu relative hidden md:block">
          <summary class="cursor-pointer list-none text-base font-medium text-stone-700 hover:text-stone-950">
            {gettext("Learn")} <span aria-hidden="true" class="text-xs">▾</span>
          </summary>
          <div class="absolute left-0 z-50 mt-2 w-64 overflow-hidden rounded-xl border border-stone-200 bg-white shadow-lg">
            <.link
              :for={{id, label, href} <- learn_items(@locale)}
              id={"learn-#{id}"}
              navigate={href}
              class="block px-4 py-3 font-semibold hover:bg-brand-wash"
            >{label}</.link>
          </div>
        </details>
        <.link
          class="hidden text-base font-medium text-brand-ink hover:text-stone-950 md:inline"
          navigate={if(@locale == "fr", do: ~p"/fr/signal-d-alarme", else: ~p"/en/warning-shot")}
        >
          {gettext("Warning shot")}
        </.link>
        <.link
          id="donate-link"
          navigate={if @locale == "fr", do: ~p"/fr/faire-un-don", else: ~p"/en/donate"}
          class="shrink-0 whitespace-nowrap rounded-full bg-brand px-3 py-2 text-sm font-bold text-stone-950 hover:bg-brand-strong sm:px-4"
        >
          {gettext("Donate")}
        </.link>
        <%!-- The menu is CSS-only, so it still works before JavaScript loads. --%>
        <details id="involvement-menu" class="act-menu relative">
          <summary class="cursor-pointer list-none text-base font-medium text-stone-700 hover:text-stone-950">
            <span class="sr-only sm:not-sr-only">{gettext("Get involved")}</span>
            <.icon name="hero-bars-3" class="size-6 sm:hidden" />
            <span aria-hidden="true" class="hidden text-xs sm:inline">▾</span>
          </summary>
          <div class="fixed left-3 right-3 top-16 z-50 max-h-[75vh] overflow-y-auto rounded-xl border border-stone-200 bg-white shadow-lg md:absolute md:left-auto md:right-0 md:top-auto md:mt-2 md:w-64">
            <div class="border-b border-stone-100 md:hidden">
              <p class="px-4 pt-3 text-xs font-semibold uppercase text-stone-500">
                {gettext("Learn")}
              </p>
              <.link
                :for={{id, label, href} <- learn_items(@locale)}
                id={"mobile-learn-#{id}"}
                navigate={href}
                class="block px-4 py-3 font-semibold hover:bg-brand-wash"
              >{label}</.link>
            </div>
            <.link
              navigate={if(@locale == "fr", do: ~p"/fr/signal-d-alarme", else: ~p"/en/warning-shot")}
              class="block px-4 py-3 font-semibold hover:bg-brand-wash md:hidden"
            >{gettext("Warning shot")}</.link>
            <.link
              href={if(@locale == "fr", do: ~p"/fr/strategie", else: ~p"/en/strategy")}
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {gettext("Strategy")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {gettext("How concern becomes collective action")}
              </span>
            </.link>
            <.link
              href={
                if(@locale == "fr",
                  do: ~p"/fr/strategie#engagement-ladder",
                  else: ~p"/en/strategy#engagement-ladder"
                )
              }
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {gettext("Ways to take part")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {gettext("See ways to deepen your involvement")}
              </span>
            </.link>
            <a
              href={
                if(@locale == "fr",
                  do: "/fr/comprendre#local-participation",
                  else: "/en/learn#local-participation"
                )
              }
              target="_blank"
              rel="noopener noreferrer"
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {gettext("Join or start a group")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {gettext("Local activities and organizing")}
              </span>
            </a>
            <a
              href="https://luma.com/calendar/cal-tsYv79s4aTQC16Q"
              target="_blank"
              rel="noopener noreferrer"
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {gettext("Events")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {gettext("Canada-wide calendar")}
              </span>
            </a>
            <.link
              id="act-email-mp"
              navigate={
                if(@locale == "fr",
                  do: ~p"/fr/signal-d-alarme#letter",
                  else: ~p"/en/warning-shot#letter"
                )
              }
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {gettext("Email your MP")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {gettext("Send a personal letter")}
              </span>
            </.link>
            <.link
              id="act-join"
              navigate={
                if(@locale == "fr", do: ~p"/fr/comprendre#updates", else: ~p"/en/learn#updates")
              }
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {gettext("Subscribe")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {gettext("Stay informed")}
              </span>
            </.link>
            <%!-- New tab: these leave for another site, and a visitor part-way
                 through reading should not lose their place. --%>
            <a
              :for={{id, label, note, href} <- act_items(@locale)}
              id={id}
              href={href}
              target="_blank"
              rel="noopener noreferrer"
              class="block border-b border-stone-100 px-4 py-3 last:border-0 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">{label}</span>
              <span class="block text-xs leading-5 text-stone-500">{note}</span>
            </a>
          </div>
        </details>

        <.link
          class="hidden text-base font-medium text-stone-700 hover:text-stone-950 lg:inline"
          href={if(@locale == "fr", do: ~p"/fr/a-propos", else: ~p"/en/about")}
        >{gettext("About")}</.link>

        <%= if @current_scope do %>
          <details id="account-menu" class="act-menu relative">
            <summary class="max-w-24 cursor-pointer list-none truncate text-base font-medium text-stone-700 hover:text-stone-950 sm:max-w-48">
              {@current_scope.user.email}
              <span aria-hidden="true" class="text-xs">▾</span>
            </summary>
            <div class="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-xl border border-stone-200 bg-white p-2 shadow-lg">
              <.link
                navigate={if(@locale == "fr", do: ~p"/fr/tableau-de-bord", else: ~p"/en/dashboard")}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{gettext("My dashboard")}</.link>
              <.link
                navigate={if(@locale == "fr", do: ~p"/fr/profil", else: ~p"/en/profile")}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{gettext("My profile")}</.link>
              <div role="separator" class="my-2 border-t border-stone-200"></div>
              <.link
                href={~p"/users/settings"}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{gettext("Settings")}</.link>
              <.link
                href={~p"/users/settings#password_form"}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{gettext("Change password")}</.link>
              <div
                :if={PauseAiCa.Volunteers.allowed?(@current_scope)}
                id="account-management-links"
                class="my-2 border-t border-stone-200 pt-2"
              >
                <p class="px-3 py-1 text-xs font-semibold uppercase tracking-wide text-stone-500">
                  {gettext("Management")}
                </p>
                <.link
                  navigate={~p"/manage/accounts?locale=#{@locale}"}
                  class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
                >{gettext("Accounts")}</.link>
                <.link
                  :if={@current_scope.user.superadmin}
                  navigate={~p"/admin/dashboard"}
                  class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
                >{gettext("Admin dashboard")}</.link>
              </div>
              <div role="separator" class="my-2 border-t border-stone-200"></div>
              <a
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
                href={@translated_path || if(@locale == "fr", do: ~p"/en", else: ~p"/fr")}
                lang={if @locale == "fr", do: "en", else: "fr"}
                hreflang={if @locale == "fr", do: "en", else: "fr"}
              >
                {gettext("Français")}
              </a>
              <.link
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-700 hover:bg-brand-wash hover:text-stone-950"
                href={~p"/users/log-out"}
                method="delete"
              >
                {gettext("Log out")}
              </.link>
            </div>
          </details>
        <% else %>
          <a
            class="text-base font-medium text-stone-600 hover:text-stone-950"
            href={@translated_path || if(@locale == "fr", do: ~p"/en", else: ~p"/fr")}
            lang={if @locale == "fr", do: "en", else: "fr"}
            hreflang={if @locale == "fr", do: "en", else: "fr"}
          >
            {gettext("Français")}
          </a>
          <.link
            id="account-entry"
            class="whitespace-nowrap rounded-full bg-stone-900 px-3 py-2 text-sm font-semibold text-white hover:bg-stone-700 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand sm:px-4 sm:text-base"
            href={~p"/users/log-in?#{%{from: "header", locale: @locale}}"}
          >
            <span class="sm:hidden">{gettext("Account")}</span>
            <span class="hidden sm:inline">{gettext("Sign in / Sign up")}</span>
          </.link>
        <% end %>
      </nav>
    </header>

    <div
      :if={@show_announcements}
      id="announcement-banners"
      class="sticky top-[var(--header-height)] z-30"
    >
      <a
        id="montreal-protest-banner"
        href={
          if @locale == "fr",
            do: ~p"/fr/manifestation-montreal-2026-09-26",
            else: ~p"/en/montreal-protest-2026-09-26"
        }
        phx-hook=".TrackOutbound"
        data-event="montreal-protest-2026-09-26"
        class="block bg-stone-950 px-5 py-3 text-center text-white transition hover:bg-stone-800 focus-visible:outline-2 focus-visible:outline-offset-[-3px] focus-visible:outline-white"
      >
        <span class="font-heading text-sm font-bold uppercase tracking-[0.16em]">
          {gettext("Montréal · Public protest")}
        </span>
        <span class="ml-2 text-sm underline underline-offset-4">
          {gettext("September 26 · Read the recap")}
          <span aria-hidden="true">→</span>
        </span>
      </a>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".TrackOutbound">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const event = this.el.dataset.event
              const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

              fetch(`/engagement/event-links/${event}`, {
                method: "POST",
                headers: {"x-csrf-token": csrfToken},
                keepalive: true
              }).catch(() => {})

              if (window.gtag) {
                window.gtag("event", "select_content", {
                  content_type: "event_recap",
                  content_id: event
                })
              }
            })
          }
        }
      </script>

      <.link
        :if={@promote_warning_shot}
        id="warning-shot-banner"
        navigate={if(@locale == "fr", do: ~p"/fr/signal-d-alarme", else: ~p"/en/warning-shot")}
        class="block bg-brand px-5 py-3 text-center text-stone-950 transition hover:bg-brand-strong"
      >
        <span class="font-heading text-sm font-bold uppercase tracking-[0.16em]">
          {gettext("Warning Shot Protocol · Second activation")}
        </span>
        <span class="ml-2 text-sm underline underline-offset-4">
          {gettext("An AI escaped its lab and hacked a real company")}
          <span aria-hidden="true">→</span>
        </span>
      </.link>
    </div>

    <.campaign_prompt
      :if={@show_announcements and @promote_warning_shot}
      locale={@locale}
      campaign_id="warning-shot-2"
      href={if(@locale == "fr", do: ~p"/fr/signal-d-alarme", else: ~p"/en/warning-shot")}
    />

    <main>
      {render_slot(@inner_block)}
    </main>

    <footer class="border-t border-stone-200">
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-start gap-x-4 px-4 py-2 text-sm text-stone-500 sm:gap-x-5 sm:px-5">
        <.link
          class="inline-flex min-h-8 items-center whitespace-nowrap hover:text-stone-900 sm:mr-auto"
          href={if(@locale == "fr", do: ~p"/fr/a-propos", else: ~p"/en/about")}
        >{gettext("PauseAI Canada")} – {gettext("About")}</.link>
        <a
          class="inline-flex min-h-8 items-center whitespace-nowrap hover:text-stone-900"
          href="https://luma.com/pauseaimtl"
          target="_blank"
          rel="noopener noreferrer"
        >{gettext("Montréal events")}</a>
        <.link
          class="inline-flex min-h-8 items-center whitespace-nowrap hover:text-stone-900"
          href={if(@locale == "fr", do: ~p"/fr/confidentialite", else: ~p"/en/privacy")}
        >{gettext("Privacy")}</.link>
        <.link
          id="hosting-location"
          href={if(@locale == "fr", do: ~p"/fr/a-propos#technical", else: ~p"/en/about#technical")}
          class="inline-flex min-h-8 items-center gap-1 whitespace-nowrap hover:text-stone-900"
        >{gettext("Made in Canada")} <span aria-hidden="true">🇨🇦</span></.link>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    <.analytics measurement_id={analytics_id()} locale={@locale} />
    <div
      :if={Phoenix.Flash.get(@flash, :signup_metric)}
      id="signup-success-event"
      phx-hook=".SignupSuccess"
      phx-update="ignore"
      hidden
      data-event={Phoenix.Flash.get(@flash, :signup_metric)}
    />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SignupSuccess">
      export default {
        mounted() {
          try { window.pauseaiSignupAnalytics.queue(JSON.parse(this.el.dataset.event)) } catch (_e) {}
        }
      }
    </script>
    """
  end

  defp analytics_id, do: Application.get_env(:pauseai_ca, :ga_measurement_id)

  # Red for the environment that looks most like production and is not it.
  defp env_badge_colour do
    if PauseAiCa.Environment.label() == "STAGING", do: "#b91c1c", else: "#1d4ed8"
  end

  # The remaining PauseAI Global actions leave this site, so each says where it
  # goes rather than pretending to be a local page.
  defp act_items(locale) do
    [
      {"act-sign", gettext("Sign"), gettext("The PauseAI statement"), act_path("sign", locale)},
      {"act-actions", gettext("Actions"), gettext("What PauseAI asks people to do"),
       act_path("actions", locale)}
    ]
  end

  defp act_path(destination, locale), do: ~p"/act/#{destination}?locale=#{locale}"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed left-1/2 top-[calc(var(--header-height)+0.75rem)] z-50 flex w-[calc(100%-2rem)] max-w-96 -translate-x-1/2 flex-col gap-2"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  defp learn_items(locale) do
    [
      {"test", gettext("Take the test"),
       if(locale == "fr", do: ~p"/fr#questions", else: ~p"/en#questions")},
      {"risks", gettext("Learn about the risks"),
       if(locale == "fr", do: ~p"/fr/comprendre", else: ~p"/en/learn")},
      {"basket", gettext("My learning list"),
       if(locale == "fr",
         do: ~p"/fr/comprendre#my-learning-list",
         else: ~p"/en/learn#my-learning-list"
       )}
    ]
  end

  @doc "Task-focused layout for management and administration."
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :locale, :string, default: nil
  attr :translated_path, :string, default: nil
  attr :active_tab, :string, default: "accounts"
  slot :inner_block, required: true

  def management(assigns) do
    ~H"""
    <.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={@translated_path}
      show_announcements={false}
    >
      <.management_tabs current_scope={@current_scope} locale={@locale} active={@active_tab} />
      {render_slot(@inner_block)}
    </.app>
    """
  end

  attr :current_scope, :map, required: true
  attr :locale, :string, default: "en"
  attr :active, :string, default: "accounts"

  def management_tabs(assigns) do
    assigns = assign(assigns, :locale, assigns.locale || Gettext.get_locale(PauseAiCaWeb.Gettext))

    assigns =
      assign(assigns, :superadmin?, PauseAiCa.Volunteers.superadmin?(assigns.current_scope))

    ~H"""
    <nav
      id="management-tabs"
      aria-label={gettext("Management")}
      class="mx-auto flex max-w-6xl items-end gap-1 border-b border-stone-300 px-5 pt-5 text-sm"
    >
      <div
        id="management-tab-links"
        phx-hook=".ManagementTabs"
        class="flex min-w-0 flex-1 overflow-x-auto"
      >
        <.link
          navigate={~p"/manage/accounts?locale=#{@locale}"}
          aria-current={if @active == "accounts", do: "page"}
          class={tab_class(@active == "accounts")}
        >{gettext("Accounts")}</.link>
        <.link
          navigate={~p"/admin/contacts?locale=#{@locale}"}
          aria-current={if @active == "contacts", do: "page"}
          class={tab_class(@active == "contacts")}
        >{gettext("Contacts")}</.link>
        <.link
          navigate={~p"/manage/mail?locale=#{@locale}"}
          aria-current={if @active == "mail", do: "page"}
          class={tab_class(@active == "mail")}
        >{gettext("Email drafts")}</.link>
        <.link
          :if={@superadmin?}
          navigate={~p"/manage/administrators?locale=#{@locale}"}
          aria-current={if @active == "administrators", do: "page"}
          class={tab_class(@active == "administrators")}
        >{gettext("Administrators")}</.link>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ManagementTabs">
        export default {
          mounted() { this.showCurrent() },
          updated() { this.showCurrent() },
          showCurrent() {
            const current = this.el.querySelector('[aria-current="page"]')
            if (!current || this.activeHref === current.href) return
            this.activeHref = current.href
            const left = current.getBoundingClientRect().left - this.el.getBoundingClientRect().left + this.el.scrollLeft
            this.el.scrollLeft = left - (this.el.clientWidth - current.offsetWidth) / 2
          }
        }
      </script>
      <details :if={@superadmin?} id="management-more" class="act-menu relative shrink-0">
        <summary class="cursor-pointer list-none border-b-2 border-transparent px-3 py-3 font-semibold">
          {gettext("More")} ▾
        </summary>
        <div class="absolute right-0 z-50 min-w-64 rounded-lg border border-stone-200 bg-white p-2 shadow-lg">
          <.link
            navigate={~p"/admin/dashboard?locale=#{@locale}"}
            aria-current={if @active == "dashboard", do: "page"}
            class="block px-3 py-2 hover:bg-brand-wash"
          >{gettext("Dashboard")}</.link>
          <.link
            navigate={~p"/admin/contact-imports?locale=#{@locale}"}
            class="block px-3 py-2 hover:bg-brand-wash"
          >{gettext("Contact imports")}</.link>
          <.link
            navigate={~p"/admin/donation-pledges?locale=#{@locale}"}
            class="block px-3 py-2 hover:bg-brand-wash"
          >{gettext("Donation pledges")}</.link>
          <a href="/admin/versions" class="block px-3 py-2 hover:bg-brand-wash">{gettext(
            "Deployment versions"
          )}</a>
          <a href="/admin/acceptance" class="block px-3 py-2 hover:bg-brand-wash">{gettext(
            "Acceptance evidence"
          )}</a>
        </div>
      </details>
    </nav>
    """
  end

  defp tab_class(active),
    do: [
      "whitespace-nowrap border-b-2 px-3 py-3 font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand",
      if(active,
        do: "border-brand text-stone-950",
        else: "border-transparent text-stone-600 hover:border-stone-400 hover:text-stone-950"
      )
    ]
end
