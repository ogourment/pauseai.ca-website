defmodule PauseAiCaWeb.ProfileComponents do
  use PauseAiCaWeb, :html

  attr :locale, :string, required: true
  attr :current, :atom, values: [:personal, :volunteer], required: true

  def profile_navigation(assigns) do
    pages = [
      {:personal, gettext("My profile"), personal_path(assigns.locale)},
      {:volunteer, gettext("Volunteer profile"), volunteer_path(assigns.locale)}
    ]

    assigns = assign(assigns, :pages, pages)

    ~H"""
    <nav
      aria-label={gettext("Profile pages")}
      class="flex flex-wrap gap-1 border-b border-stone-200 pb-2"
    >
      <.link
        :for={{page, label, path} <- @pages}
        id={if page == :volunteer, do: "volunteer-profile-link"}
        navigate={path}
        aria-current={if page == @current, do: "page"}
        class={[
          "inline-flex min-h-11 items-center rounded-lg px-3 text-sm font-semibold hover:bg-stone-100",
          if(page == @current,
            do: "bg-stone-100 text-green-900 shadow-[inset_0_-2px_currentColor]",
            else: "text-stone-900"
          )
        ]}
      >{label}</.link>
    </nav>
    """
  end

  def form_styles do
    [
      "[&_.label]:text-stone-700 [&_.text-error]:text-red-800",
      "[&_.input:not(.input-error)]:border-stone-500 [&_.input::placeholder]:text-stone-600",
      "[&_.select:not(.select-error)]:border-stone-500",
      "[&_.textarea:not(.textarea-error)]:border-stone-500 [&_.textarea::placeholder]:text-stone-600",
      "[&_.checkbox]:border-stone-500 [&_input[type=checkbox]]:accent-stone-900 [&_input[type=radio]]:accent-stone-900"
    ]
  end

  def action_class do
    "rounded-lg bg-stone-900 px-4 py-2 text-sm font-semibold text-white hover:bg-stone-700 " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-900 " <>
      "disabled:bg-stone-200 disabled:text-stone-600"
  end

  def personal_path("fr"), do: ~p"/fr/profil"
  def personal_path(_), do: ~p"/en/profile"

  defp volunteer_path("fr"), do: ~p"/fr/profil/benevolat"
  defp volunteer_path(_), do: ~p"/en/profile/volunteer"
end
