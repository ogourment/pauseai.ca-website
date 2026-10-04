[
  %{id: "identity", title: "Identity", tables: ["users", "users_tokens"]},
  %{
    id: "engagement",
    title: "Engagement and learning",
    tables: ["actions", "learning_signals", "learning_game_attempts", "quiz_question_drafts", "quiz_question_revisions"]
  },
  %{id: "crm", title: "Contact identity", tables: ~w(crm_people crm_addresses crm_sources crm_activities crm_merges crm_contact_links)},
  %{id: "mail_drafts", title: "Email drafts", tables: ~w(mail_batches mail_drafts)},
  %{
    id: "newsletter",
    title: "Newsletter consent",
    tables: ~w(newsletter_subscriptions newsletter_consent_events newsletter_withdrawal_tokens)
  },
  %{id: "outreach", title: "Outreach", tables: ["pending_letters"]},
  %{
    id: "contact_migration",
    title: "Contact migration",
    tables: ["contact_activities", "contact_imports", "contacts"]
  },
  %{
    id: "volunteers",
    title: "Volunteer signup and profiles",
    tables: [
      "volunteer_groups",
      "volunteer_group_managers",
      "volunteer_batches",
      "volunteer_profiles",
      "volunteer_signups",
      "volunteer_invitations",
      "volunteer_events"
    ]
  },
  %{id: "donations", title: "Donation pledges", tables: ["donation_pledges"]},
  %{id: "analytics", title: "First-party analytics", tables: ["daily_visits"]},
  %{
    id: "acceptance_evidence",
    title: "Acceptance evidence",
    tables: [
      "acceptance_harness_runs",
      "acceptance_harness_scenarios",
      "acceptance_harness_steps"
    ]
  },
  %{id: "platform", title: "Database platform", tables: ["schema_migrations"]}
]
