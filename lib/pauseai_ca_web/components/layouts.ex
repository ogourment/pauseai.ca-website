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

  attr :locale, :string, default: "en"

  attr :translated_path, :string,
    default: nil,
    doc: "where the language switch should go; defaults to the other home page"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 border-b border-stone-200/80 bg-[#f8f5ed]/95 backdrop-blur">
      <nav class="mx-auto flex max-w-6xl items-center gap-5 px-5 py-4" aria-label="Main navigation">
        <a
          href={if(@locale == "fr", do: ~p"/fr", else: ~p"/en")}
          class="mr-auto flex items-center gap-3"
        >
          <span class="relative inline-flex">
            <img src={~p"/images/pauseai-ca.png"} alt="" width="36" height="36" class="size-9" />
            <span
              :if={PauseAiCa.Environment.badged?()}
              class="pointer-events-none absolute -right-3 top-1/4 -translate-y-1/2 rotate-[-12deg] rounded-[3px] px-1.5 py-0.5 text-[10px] font-black uppercase leading-none tracking-wide text-white shadow-sm"
              style={"background: #{env_badge_colour()}"}
            >
              {PauseAiCa.Environment.label()}
            </span>
          </span>
          <span class="font-semibold tracking-tight text-stone-900">PauseAI Canada</span>
        </a>
        <.link
          class="text-base font-medium text-stone-700 hover:text-stone-950"
          navigate={if(@locale == "fr", do: ~p"/fr/comprendre", else: ~p"/en/learn")}
        >
          {if(@locale == "fr", do: "Comprendre", else: "Learn")}
        </.link>
        <.link
          class="text-base font-medium text-brand-ink hover:text-stone-950"
          navigate={if(@locale == "fr", do: ~p"/fr/tir-de-semonce", else: ~p"/en/warning-shot")}
        >
          {if(@locale == "fr", do: "Tir de semonce", else: "Warning shot")}
        </.link>
        <%!-- The menu is CSS-only, so it still works before JavaScript loads. --%>
        <details id="involvement-menu" class="act-menu relative">
          <summary class="cursor-pointer list-none text-base font-medium text-stone-700 hover:text-stone-950">
            {if(@locale == "fr", do: "S'impliquer", else: "Get involved")}
            <span aria-hidden="true" class="text-xs">▾</span>
          </summary>
          <div class="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-xl border border-stone-200 bg-white shadow-lg">
            <.link
              href={if(@locale == "fr", do: ~p"/fr/strategie", else: ~p"/en/strategy")}
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {if(@locale == "fr", do: "Stratégie", else: "Strategy")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {if(@locale == "fr",
                  do: "Comment passer de l'intérêt à l'action collective",
                  else: "How concern becomes collective action"
                )}
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
                {if(@locale == "fr", do: "Échelle d'engagement", else: "Engagement ladder")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {if(@locale == "fr",
                  do: "Voir les façons de progresser",
                  else: "See ways to deepen your involvement"
                )}
              </span>
            </.link>
            <a
              href="https://pauseai.info/local-organizing"
              target="_blank"
              rel="noopener noreferrer"
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {if(@locale == "fr", do: "Lancer un groupe", else: "Start a group")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {if(@locale == "fr",
                  do: "Guide de PauseAI Global",
                  else: "PauseAI Global's chapter guide"
                )}
              </span>
            </a>
            <a
              href="https://luma.com/calendar/cal-tsYv79s4aTQC16Q"
              target="_blank"
              rel="noopener noreferrer"
              class="block border-b border-stone-100 px-4 py-3 hover:bg-brand-wash"
            >
              <span class="block font-heading text-base font-bold text-stone-950">
                {if(@locale == "fr", do: "Événements", else: "Events")}
              </span>
              <span class="block text-xs leading-5 text-stone-500">
                {if(@locale == "fr", do: "Calendrier canadien", else: "Canada-wide calendar")}
              </span>
            </a>
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
        >{if(@locale == "fr", do: "À propos", else: "About")}</.link>

        <%= if @current_scope do %>
          <details id="account-menu" class="act-menu relative">
            <summary class="max-w-48 cursor-pointer list-none truncate text-base font-medium text-stone-700 hover:text-stone-950">
              {@current_scope.user.email}
              <span aria-hidden="true" class="text-xs">▾</span>
            </summary>
            <div class="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-xl border border-stone-200 bg-white p-2 shadow-lg">
              <.link
                navigate={if(@locale == "fr", do: ~p"/fr/actions", else: ~p"/en/actions")}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{if(@locale == "fr", do: "Mes actions", else: "My actions")}</.link>
              <div role="separator" class="my-2 border-t border-stone-200"></div>
              <.link
                href={~p"/users/settings"}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{if(@locale == "fr", do: "Paramètres", else: "Settings")}</.link>
              <.link
                href={~p"/users/settings#password_form"}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >{if(@locale == "fr", do: "Changer le mot de passe", else: "Change password")}</.link>
              <div
                :if={@current_scope.user.superadmin}
                role="separator"
                class="my-2 border-t border-stone-200"
              >
              </div>
              <.link
                :if={@current_scope.user.superadmin}
                navigate={~p"/admin/metrics"}
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
              >Admin</.link>
              <div role="separator" class="my-2 border-t border-stone-200"></div>
              <a
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-900 hover:bg-brand-wash"
                href={@translated_path || if(@locale == "fr", do: ~p"/en", else: ~p"/fr")}
              >
                {if(@locale == "fr", do: "Passer à l'anglais", else: "Passer au français")}
              </a>
              <.link
                class="block rounded-lg px-3 py-2.5 font-semibold text-stone-700 hover:bg-brand-wash hover:text-stone-950"
                href={~p"/users/log-out"}
                method="delete"
              >
                {if(@locale == "fr", do: "Déconnexion", else: "Log out")}
              </.link>
            </div>
          </details>
        <% else %>
          <a
            class="text-base font-medium text-stone-600 hover:text-stone-950"
            href={@translated_path || if(@locale == "fr", do: ~p"/en", else: ~p"/fr")}
          >
            {if(@locale == "fr", do: "English", else: "Français")}
          </a>
          <.link
            class="rounded-full bg-stone-900 px-4 py-2 text-base font-semibold text-white hover:bg-stone-700"
            href={~p"/users/log-in"}
          >
            {if(@locale == "fr", do: "Se connecter", else: "Sign in")}
          </.link>
        <% end %>
      </nav>
    </header>

    <main>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    <.analytics measurement_id={analytics_id()} locale={@locale} />
    """
  end

  defp analytics_id, do: Application.get_env(:pauseai_ca, :ga_measurement_id)

  # Red for the environment that looks most like production and is not it.
  defp env_badge_colour do
    if PauseAiCa.Environment.label() == "STAGING", do: "#b91c1c", else: "#1d4ed8"
  end

  # The three things PauseAI Global asks people to do. They all leave this site,
  # so each says where it goes rather than pretending to be a local page.
  defp act_items("fr") do
    [
      {"act-join", "Rejoindre", "Formulaire mondial de PauseAI", act_path("join", "fr")},
      {"act-sign", "Signer", "La déclaration de PauseAI", act_path("sign", "fr")},
      {"act-actions", "Passer à l'action", "Les actions proposées par PauseAI",
       act_path("actions", "fr")}
    ]
  end

  defp act_items(_locale) do
    [
      {"act-join", "Join", "PauseAI's global form", act_path("join", "en")},
      {"act-sign", "Sign", "The PauseAI statement", act_path("sign", "en")},
      {"act-actions", "Actions", "What PauseAI asks people to do", act_path("actions", "en")}
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
    <div id={@id} aria-live="polite">
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
end
