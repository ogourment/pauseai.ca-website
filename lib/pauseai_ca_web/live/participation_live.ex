defmodule PauseAiCaWeb.ParticipationLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Accounts.Onboarding

  @impl true
  def mount(params, session, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    context =
      Onboarding.context(Map.put(params, "locale", locale), session["learning_visitor_id"])

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Get involved"),
       context: context,
       intent: params["intent"] || "action",
       city: params["city"] || "",
       registration: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale}>
      <div class="mx-auto max-w-5xl px-5 py-12">
        <.live_component
          module={PauseAiCaWeb.ParticipationForm}
          id="participation-entry"
          locale={@locale}
          current_scope={@current_scope}
          context={@context}
          intent={@intent}
          city={@city}
          registration={@registration}
          show_ctas={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
