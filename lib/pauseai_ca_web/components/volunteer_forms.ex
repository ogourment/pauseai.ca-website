defmodule PauseAiCaWeb.VolunteerForms do
  use PauseAiCaWeb, :html

  attr :form, :any, required: true
  attr :errors, :map, default: %{}
  attr :step, :string, required: true

  def profile_fields(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-2">
      <%= if @step == "contact" do %>
        <.input
          field={@form[:contact_preference]}
          errors={
            if @errors["contact_preference"], do: [error(@errors["contact_preference"])], else: []
          }
          type="select"
          label={gettext("Preferred contact method")}
          options={[
            {gettext("Not specified"), ""},
            {gettext("Email"), "email"},
            {"Discord", "discord"},
            {"Signal", "signal"},
            {"WhatsApp", "whatsapp"}
          ]}
        />
        <.input
          field={@form[:discord_handle]}
          errors={if @errors["discord_handle"], do: [error(@errors["discord_handle"])], else: []}
          label="Discord"
        />
        <.input
          field={@form[:signal_number]}
          errors={if @errors["signal_number"], do: [error(@errors["signal_number"])], else: []}
          label="Signal"
        />
        <.input
          field={@form[:whatsapp_number]}
          errors={if @errors["whatsapp_number"], do: [error(@errors["whatsapp_number"])], else: []}
          label="WhatsApp"
        />
        <.input
          field={@form[:city]}
          errors={if @errors["city"], do: [error(@errors["city"])], else: []}
          label={gettext("City")}
        />
        <.input
          field={@form[:country]}
          errors={if @errors["country"], do: [error(@errors["country"])], else: []}
          label={gettext("Country")}
        />
        <.input
          field={@form[:contact_notes]}
          errors={if @errors["contact_notes"], do: [error(@errors["contact_notes"])], else: []}
          type="textarea"
          label={gettext("Contact instructions")}
        />
      <% else %>
        <.input
          field={@form[:bio]}
          errors={if @errors["bio"], do: [error(@errors["bio"])], else: []}
          type="textarea"
          label={gettext("About me")}
        />
        <.input
          field={@form[:availability_hours_per_week]}
          errors={
            if @errors["availability_hours_per_week"],
              do: [error(@errors["availability_hours_per_week"])],
              else: []
          }
          type="number"
          min="0"
          max="168"
          label={gettext("Hours available per week")}
        />
        <.input
          field={@form[:skills]}
          errors={if @errors["skills"], do: [error(@errors["skills"])], else: []}
          type="textarea"
          label={gettext("Skills and proficiency")}
          placeholder={gettext("For example: Organizing / Facilitation: advanced")}
        />
        <.input
          field={@form[:other_skills]}
          errors={if @errors["other_skills"], do: [error(@errors["other_skills"])], else: []}
          type="textarea"
          label={gettext("Other skills")}
        />
        <.input
          field={@form[:application_message]}
          errors={
            if @errors["application_message"], do: [error(@errors["application_message"])], else: []
          }
          type="textarea"
          label={gettext("What would you like to help with?")}
        />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :value, :any, required: true
  attr :locale, :string, required: true

  def timestamp(assigns) do
    ~H"""
    <time
      :if={@value}
      id={@id}
      datetime={DateTime.to_iso8601(@value)}
      data-locale={@locale}
      phx-hook=".LocalTime"
    >{Calendar.strftime(@value, "%Y-%m-%d %H:%M UTC")}</time>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      export default {
        mounted() { this.renderTime() },
        updated() { this.renderTime() },
        renderTime() {
          this.el.textContent = new Intl.DateTimeFormat(this.el.dataset.locale, {
            weekday: "short", year: "numeric", month: "short", day: "numeric",
            hour: "numeric", minute: "2-digit", timeZoneName: "short"
          }).format(new Date(this.el.dateTime))
        }
      }
    </script>
    """
  end

  def label("name"), do: gettext("Name")
  def label("email"), do: gettext("Email")
  def label("postal_code"), do: gettext("Postal code")
  def label("city"), do: gettext("City")
  def label("country"), do: gettext("Country")
  def label("group_id"), do: gettext("Incubator / group")
  def label("notes"), do: gettext("Private organizer notes")
  def label("bio"), do: gettext("About me")
  def label("discord_handle"), do: "Discord"
  def label("signal_number"), do: "Signal"
  def label("whatsapp_number"), do: "WhatsApp"
  def label("contact_preference"), do: gettext("Preferred contact method")
  def label("contact_notes"), do: gettext("Contact instructions")
  def label("availability_hours_per_week"), do: gettext("Hours available per week")
  def label("skills"), do: gettext("Skills and proficiency")
  def label("other_skills"), do: gettext("Other skills")
  def label("application_message"), do: gettext("What would you like to help with?")

  def error(:required), do: gettext("This field is required.")
  def error(:invalid_email), do: gettext("Enter a valid email address.")
  def error(:invalid_postal_code), do: gettext("Enter a complete Canadian postal code.")

  def error(:invalid_skills),
    do:
      gettext(
        "Use one skill per line: category / skill: beginner, intermediate, advanced or expert."
      )

  def error(:invalid_hours), do: gettext("Enter a whole number from 0 to 168.")
  def error(:invalid_preference), do: gettext("Choose one of the contact methods.")
  def error(:too_long), do: gettext("This value is too long.")
  def error(:duplicate), do: gettext("Duplicate email in this sheet. Keep one row.")
  def error(:unauthorized_group), do: gettext("Choose a group you manage.")
  def error(:suppressed), do: gettext("Do not contact. Invitation excluded.")
  def error(:already_imported), do: gettext("Previously imported. No automatic resend.")
  def error(:needs_admin), do: gettext("An administrator must review this row.")

  def action("batch_confirmed"), do: gettext("Batch confirmed")
  def action("account_updated"), do: gettext("Account updated")
  def action("account_linked"), do: gettext("Account linked")
  def action("invitation_retry_requested"), do: gettext("Retry requested")
  def action("invitation_resend_requested"), do: gettext("Resend requested")
  def action("invitation_reconciled"), do: gettext("Provider outcome verified")
  def action("invitation_" <> status), do: status(status)

  def status(:new_account), do: gettext("New account")
  def status(:existing_account), do: gettext("Existing account")
  def status(:already_imported), do: gettext("Previously imported")
  def status(:suppressed), do: gettext("Do not contact")
  def status(:needs_admin), do: gettext("Needs administrator review")
  def status("queued"), do: gettext("Queued")
  def status("sending"), do: gettext("Sending")
  def status("accepted"), do: gettext("Accepted by email provider")
  def status("failed"), do: gettext("Failed — retry available")
  def status("unknown"), do: gettext("Delivery unknown — reconcile before retry")
  def status("suppressed"), do: gettext("Do not contact")
  def status("resent"), do: gettext("Resend requested")
  def status("retried"), do: gettext("Retry requested")
end
