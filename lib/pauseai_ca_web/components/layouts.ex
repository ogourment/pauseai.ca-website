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
          <img
            src={~p"/images/pauseai-ca.png"}
            alt=""
            width="36"
            height="36"
            class="size-9"
          />
          <span class="font-semibold tracking-tight text-stone-900">PauseAI Canada</span>
        </a>
        <.link
          class="text-sm font-medium text-stone-700 hover:text-stone-950"
          navigate={if(@locale == "fr", do: ~p"/fr/comprendre", else: ~p"/en/learn")}
        >
          {if(@locale == "fr", do: "Comprendre", else: "Learn")}
        </.link>
        <.link
          class="text-sm font-medium text-brand-ink hover:text-stone-950"
          navigate={if(@locale == "fr", do: ~p"/fr/tir-de-semonce", else: ~p"/en/warning-shot")}
        >
          {if(@locale == "fr", do: "Tir de semonce", else: "Warning shot")}
        </.link>
        <a
          class="text-sm font-medium text-stone-600 hover:text-stone-950"
          href={@translated_path || if(@locale == "fr", do: ~p"/en", else: ~p"/fr")}
        >
          {if(@locale == "fr", do: "English", else: "Français")}
        </a>
        <%= if @current_scope do %>
          <.link class="hidden text-sm text-stone-500 sm:inline" href={~p"/users/settings"}>
            {@current_scope.user.email}
          </.link>
          <.link
            class="text-sm font-medium text-stone-700 hover:text-stone-950"
            navigate={~p"/dashboard"}
          >
            {if(@locale == "fr", do: "Mes actions", else: "My actions")}
          </.link>
          <.link
            class="text-sm font-medium text-stone-600 hover:text-stone-950"
            href={~p"/users/log-out"}
            method="delete"
          >
            {if(@locale == "fr", do: "Déconnexion", else: "Log out")}
          </.link>
        <% else %>
          <.link
            class="rounded-full bg-stone-900 px-4 py-2 text-sm font-semibold text-white hover:bg-stone-700"
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
    """
  end

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
