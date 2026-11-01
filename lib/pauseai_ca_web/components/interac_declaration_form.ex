defmodule PauseAiCaWeb.InteracDeclarationForm do
  @moduledoc "Compact private matching declaration, shared with the inert donation CMS preview."
  use PauseAiCaWeb, :html
  attr :form, :any, default: nil
  attr :submission_token, :string, default: nil
  attr :saved, :boolean, default: false
  attr :linked_account, :boolean, default: false
  attr :preview_mode, :boolean, default: false

  def declaration(assigns) do
    assigns =
      assign(assigns,
        form:
          assigns.form ||
            to_form(%{"name" => "", "email" => "", "amount" => "", "anonymous" => "true"},
              as: "interac"
            ),
        prefix: if(assigns.preview_mode, do: "interac-preview", else: "interac-declaration")
      )

    ~H"""
    <section id={@prefix} class="mt-5 max-w-2xl rounded-lg border border-stone-300 bg-white p-4">
      <h3 class="font-heading text-xl">{gettext("Help us match your transfer")}</h3>
      <p class="mt-2 text-sm leading-6 text-stone-700">
        {gettext(
          "Send your transfer from your banking app. This declaration stays pending until we match it to a bank deposit."
        )}
      </p>
      <p :if={@saved} id="interac-declaration-status" role="status" class="mt-4 font-semibold">
        {gettext("Declaration recorded. Awaiting bank verification.")}
      </p>
      <.form
        :if={!@saved}
        for={@form}
        id={"#{@prefix}-form"}
        phx-change={if !@preview_mode, do: "validate_interac"}
        phx-submit={if !@preview_mode, do: "declare_interac"}
        class="mt-4 space-y-4"
      >
        <input
          type="hidden"
          name="interac[submission_token]"
          value={@submission_token}
          disabled={@preview_mode}
        />
        <p :if={@linked_account} class="text-sm text-stone-700">
          {gettext(
            "This declaration is linked to your signed-in account. Your account email is read-only here."
          )}
        </p>
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:name]}
            id={"#{@prefix}-name"}
            label={
              if @linked_account,
                do: gettext("Name shown on transfer (optional)"),
                else: gettext("Name shown on transfer")
            }
            autocomplete="name"
            maxlength="160"
            required={!@linked_account}
            disabled={@preview_mode}
          />
          <.input
            field={@form[:email]}
            id={"#{@prefix}-email"}
            type="email"
            label={if @linked_account, do: gettext("Account email"), else: gettext("Contact email")}
            autocomplete="email"
            maxlength="160"
            required
            readonly={@linked_account}
            disabled={@preview_mode}
          />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="max-w-48">
            <.input
              field={@form[:amount]}
              id={"#{@prefix}-amount"}
              label={gettext("Amount (CAD)")}
              inputmode="decimal"
              placeholder="25.00"
              required
              disabled={@preview_mode}
            />
          </div>
          <.input
            field={@form[:anonymous]}
            id={"#{@prefix}-anonymous"}
            type="select"
            label={gettext("Anonymous donation")}
            aria-label={gettext("Anonymous donation")}
            options={[{gettext("Yes"), "true"}, {gettext("No"), "false"}]}
            disabled={@preview_mode}
          />
        </div>
        <p id={"#{@prefix}-privacy"} class="text-sm leading-6 text-stone-700">
          {gettext(
            "Anonymous means no public acknowledgement. Authorized organizers still see your private matching details."
          )}
        </p>
        <div class="hidden" aria-hidden="true">
          <input name="interac[website]" tabindex="-1" autocomplete="off" disabled={@preview_mode} />
        </div>
        <button
          type="submit"
          disabled={@preview_mode}
          phx-disable-with={gettext("Recording…")}
          class="rounded-lg bg-stone-900 px-4 py-2 font-semibold text-white disabled:opacity-60"
        >
          {gettext("Record donation")}
        </button>
      </.form>
    </section>
    """
  end
end
