[
  %{id: "identity", title: "Identity", tables: ["users", "users_tokens"]},
  %{
    id: "engagement",
    title: "Engagement and learning",
    tables: ["actions", "learning_signals"]
  },
  %{id: "outreach", title: "Outreach", tables: ["pending_letters"]},
  %{
    id: "contact_migration",
    title: "Contact migration",
    tables: ["contact_activities", "contact_imports", "contacts"]
  },
  %{id: "analytics", title: "First-party analytics", tables: ["daily_visits"]},
  %{
    id: "acceptance_evidence",
    title: "Acceptance evidence",
    tables: [
      "acceptance_harness_comments",
      "acceptance_harness_runs",
      "acceptance_harness_scenarios",
      "acceptance_harness_statuses",
      "acceptance_harness_steps"
    ]
  },
  %{id: "platform", title: "Database platform", tables: ["schema_migrations"]}
]
