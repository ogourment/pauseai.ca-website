defmodule PauseAiCaWeb.ParticipationChoices do
  use PauseAiCaWeb, :html

  attr :request, :any, required: true

  def summary(assigns) do
    assigns =
      assign(assigns, :choices, [
        {gettext("PauseAI Canada newsletter"), assigns.request.newsletter},
        {gettext("Account to save and record actions"), assigns.request.account},
        {gettext("Local group follow-up"), not is_nil(assigns.request.local_kind)}
      ])

    ~H"""
    <dl id="participation-choice-summary" class="mt-4 space-y-2">
      <div :for={{label, included?} <- @choices} class="flex flex-wrap justify-between gap-x-4">
        <dt>{label}</dt>
        <dd class={if included?, do: "font-semibold", else: "text-stone-600"}>
          {if included?, do: gettext("Included"), else: gettext("Not selected")}
        </dd>
      </div>
      <div :if={@request.local_kind}>
        <dt class="sr-only">{gettext("Local request")}</dt>
        <dd>
          {if @request.local_kind == "help",
            do: gettext("Offer of help"),
            else: gettext("Local waitlist")} · {@request.city || @request.fsa}
        </dd>
      </div>
    </dl>
    <.link
      id="participation-edit-choices"
      href={
        ~p"/participation/edit?#{%{token: PauseAiCa.Participation.choices_token(@request), locale: @request.locale}}"
      }
      class="mt-4 inline-block font-semibold underline"
    >
      {gettext("Change my choices")}
    </.link>
    """
  end
end
