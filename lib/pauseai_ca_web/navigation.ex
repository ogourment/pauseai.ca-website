defmodule PauseAiCaWeb.Navigation do
  @moduledoc "PauseAI's consumer-owned shell contributions and fresh policy adapter."
  @behaviour PhoenixAppShell.NavigationContributor
  @behaviour PhoenixAppShell.HostAdapter
  use Gettext, backend: PauseAiCaWeb.Gettext
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}

  @impl true
  def navigation_items do
    [
      item("pauseai.contacts", gettext_noop("Contacts"), :admin, :contacts, :admin, 10),
      item(
        "pauseai.administrators",
        gettext_noop("Administrators"),
        :admin,
        :administrators,
        :admin,
        20
      ),
      item("pauseai.dashboard", gettext_noop("Dashboard"), :admin, :dashboard, :admin, 30),
      item(
        "pauseai.donation-pledges",
        gettext_noop("Donation pledges"),
        :admin,
        :donation_pledges,
        :admin,
        40
      ),
      item(
        "pauseai.versions",
        gettext_noop("Deployment versions"),
        :admin,
        :versions,
        :admin,
        50
      ),
      item(
        "pauseai.acceptance",
        gettext_noop("Acceptance evidence"),
        :admin,
        :acceptance,
        :admin,
        60
      ),
      item("pauseai.accounts", gettext_noop("Accounts"), :manage, :accounts, :organizer, 10),
      item("pauseai.mail", gettext_noop("Emails"), :manage, :mail, :organizer, 20),
      item("pauseai.questions", gettext_noop("Quiz"), :manage, :questions, :organizer, 30),
      item(
        "pauseai.my-dashboard",
        gettext_noop("My dashboard"),
        :account,
        :my_dashboard,
        :self,
        10
      ),
      item("pauseai.my-profile", gettext_noop("My profile"), :account, :my_profile, :self, 20),
      item("pauseai.settings", gettext_noop("Settings"), :account, :settings, :self, 30),
      item("pauseai.password", gettext_noop("Change password"), :account, :password, :self, 40)
    ]
  end

  defp item(id, label, area, route, capability, order),
    do: %{
      id: id,
      label: label,
      area: area,
      group: if(route in [:versions, :acceptance], do: :tools, else: :primary),
      order: order,
      route_key: route,
      required_capability: capability,
      context_requirements: []
    }

  def assemble(scope, locale) do
    # Reload once per assembly: a stale session role cannot keep a menu grant.
    user =
      case scope do
        %Scope{user: %{id: id}} -> Repo.get(User, id)
        _ -> nil
      end

    fresh = Scope.for_user(user)

    context = %{
      actor: fresh,
      locale: locale,
      admin: Volunteers.superadmin?(fresh),
      organizer: Volunteers.allowed?(fresh)
    }

    {:ok, items} = PhoenixAppShell.Navigation.assemble([__MODULE__], context, __MODULE__)
    items
  end

  @impl true
  def superadmin?(context), do: context.admin
  @impl true
  def authorize(%{required_capability: :admin}, context), do: context.admin
  def authorize(%{required_capability: :organizer}, context), do: context.organizer

  def authorize(%{required_capability: :self}, %{actor: %Scope{user: %User{confirmed_at: at}}}),
    do: at != nil

  def authorize(_, _), do: false

  @impl true
  def resolve_route(key, %{locale: locale}) do
    route =
      case key do
        :contacts -> "/admin/contacts"
        :administrators -> "/manage/administrators"
        :dashboard -> "/admin/dashboard"
        :donation_pledges -> "/admin/donation-pledges"
        :versions -> "/admin/versions"
        :acceptance -> "/admin/acceptance"
        :accounts -> "/manage/accounts"
        :mail -> "/manage/mail"
        :questions -> "/manage/questions"
        :my_dashboard -> if(locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard")
        :my_profile -> if(locale == "fr", do: "/fr/profil", else: "/en/profile")
        :password -> "/users/settings#password_form"
        :settings -> "/users/settings"
        _ -> nil
      end

    if route do
      {:ok,
       if(key in [:my_dashboard, :my_profile, :settings, :password, :versions, :acceptance],
         do: route,
         else: with_locale(route, locale)
       )}
    else
      :error
    end
  end

  defp with_locale(route, locale) do
    uri = URI.parse(route)
    URI.to_string(%{uri | query: URI.encode_query(%{"locale" => locale})})
  end

  def menu_items(scope, locale) do
    Enum.map(assemble(scope, locale), fn item ->
      if item.id == "pauseai.dashboard",
        do: %{item | label: gettext("Admin dashboard")},
        else: item
    end)
  end

  @impl true
  def label(%{label: label}, _context), do: Gettext.gettext(PauseAiCaWeb.Gettext, label)

  def area_labels,
    do: %{admin: gettext("Admin"), manage: gettext("Management"), account: gettext("My account")}
end
