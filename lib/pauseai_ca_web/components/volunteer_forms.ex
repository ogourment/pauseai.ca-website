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
        <.activities
          prefix="profile"
          field="selected_skills"
          selected={List.wrap(@form[:selected_skills].value)}
          experience={@form[:experience].value || %{}}
        />
        <.input
          field={@form[:share_contribution]}
          type="checkbox"
          label={label("share_contribution")}
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

  attr :prefix, :string, required: true
  attr :field, :string, required: true
  attr :selected, :list, required: true
  attr :experience, :map, required: true

  def activities(assigns) do
    ~H"""
    <fieldset class="space-y-2 sm:col-span-2">
      <legend class="font-semibold">{gettext("What would you like to try?")}</legend>
      <p>{gettext("Experience is optional.")}</p>
      <input type="hidden" name={@prefix <> "[" <> @field <> "][]"} value="" />
      <details
        :for={{group, ids} <- PauseAiCa.Volunteers.Input.skill_groups()}
        id={@prefix <> "-activities-" <> group}
        class="border-t py-2"
        open={Enum.any?(ids, &(&1 in @selected))}
      >
        <summary class="cursor-pointer font-semibold">{skill_label(group)}</summary>
        <div :for={id <- ids} class="py-1">
          <label><input
            type="checkbox"
            name={@prefix <> "[" <> @field <> "][]"}
            value={id}
            checked={id in @selected}
          /> {skill_label(id)}</label>
          <fieldset :if={id in @selected} class="ml-5 border-l pl-3">
            <legend>{gettext("Experience")} · {skill_label(id)}</legend>
            <label :for={level <- ~w(learn done guide) ++ [""]} class="block">
              <input
                type="radio"
                data-experience={id}
                name={@prefix <> "[experience][" <> id <> "]"}
                value={level}
                checked={(@experience[id] || "") == level}
              />
              {if level == "", do: gettext("Leave unanswered"), else: skill_label(level)}
            </label>
          </fieldset>
        </div>
      </details>
      <label class="block"><input
        type="checkbox"
        name={@prefix <> "[" <> @field <> "][]"}
        value="first_task"
        checked={"first_task" in @selected}
      /> {skill_label("first_task")}</label>
    </fieldset>
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

  def label("selected_skills"), do: gettext("Skills you can offer")

  def label("share_contribution"),
    do: gettext("Share my activities, experience and hours with my group managers")

  def label("experience"), do: gettext("Experience")

  def skill_label("public"), do: gettext("Talk to the public")
  def skill_label("flyers"), do: gettext("Distribute flyers")
  def skill_label("posters"), do: gettext("Put up posters")
  def skill_label("tabling"), do: gettext("Staff an information table")
  def skill_label("calls"), do: gettext("Make outreach calls")
  def skill_label("outreach"), do: gettext("Outreach")
  def skill_label("creative"), do: gettext("Make things and tell stories")
  def skill_label("photography"), do: gettext("Photograph an event")
  def skill_label("filming"), do: gettext("Film an event")
  def skill_label("video_editing"), do: gettext("Video editing")
  def skill_label("design"), do: gettext("Design flyers and posters")
  def skill_label("writing"), do: gettext("Write materials")
  def skill_label("translation"), do: gettext("Translation")
  def skill_label("signs"), do: gettext("Make signs")
  def skill_label("press"), do: gettext("Work with the press and online")
  def skill_label("pitch"), do: gettext("Pitch a local story")
  def skill_label("interview"), do: gettext("Give a media interview")
  def skill_label("press_release"), do: gettext("Write a press release")
  def skill_label("social"), do: gettext("Run social accounts")
  def skill_label("events"), do: gettext("Plan events and workshops")
  def skill_label("venue"), do: gettext("Find an accessible venue")
  def skill_label("logistics"), do: gettext("Arrange equipment or food")
  def skill_label("workshop"), do: gettext("Facilitate a workshop")
  def skill_label("march"), do: gettext("Coordinate a peaceful march")
  def skill_label("event_support"), do: gettext("Event support")
  def skill_label("facilitation"), do: gettext("Facilitation")
  def skill_label("care"), do: gettext("Welcome and care for people")
  def skill_label("welcome"), do: gettext("Welcome new members")
  def skill_label("buddy"), do: gettext("Buddy a first-time volunteer")
  def skill_label("access"), do: gettext("Arrange interpretation or remote access")
  def skill_label("care_breaks"), do: gettext("Plan breaks and check-ins")
  def skill_label("research"), do: gettext("Research and meet decision-makers")
  def skill_label("research_issue"), do: gettext("Research an issue")
  def skill_label("brief"), do: gettext("Prepare a briefing")
  def skill_label("mp"), do: gettext("Arrange an MP meeting")
  def skill_label("notes"), do: gettext("Take notes and follow up")
  def skill_label("operations"), do: gettext("Keep the group running")
  def skill_label("coordination"), do: gettext("Coordinate volunteers")
  def skill_label("funding"), do: gettext("Apply for funding")
  def skill_label("expenses"), do: gettext("Track expenses")
  def skill_label("website"), do: gettext("Maintain the website or other tools")
  def skill_label("technology"), do: gettext("Technology")
  def skill_label("first_task"), do: gettext("Help me find a first task")
  def skill_label("learn"), do: gettext("I’d like to learn")
  def skill_label("done"), do: gettext("I’ve done this before")
  def skill_label("guide"), do: gettext("I can guide someone")
  def skill_label(_), do: nil

  def profile_value("experience", levels), do: skill_summary(Map.keys(levels), levels)

  def profile_value("selected_skills", values), do: skill_summary(values)

  def profile_value("share_contribution", value) when value in [true, "true"],
    do: gettext("Managers of my groups")

  def profile_value("share_contribution", _), do: gettext("Private")
  def profile_value(_, value), do: value

  def skill_summary(values, levels \\ %{}) do
    values
    |> List.wrap()
    |> Enum.map(fn id ->
      case levels[id] do
        level when level in ~w(learn done guide) -> "#{skill_label(id)} (#{skill_label(level)})"
        _ -> skill_label(id)
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  def error(:required), do: gettext("This field is required.")
  def error(:invalid_email), do: gettext("Enter a valid email address.")
  def error(:invalid_phone), do: gettext("Enter a phone number with 7 to 20 digits.")
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
