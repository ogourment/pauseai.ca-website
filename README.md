# PauseAI Canada website

The English and French website for PauseAI Canada / PauseIA Canada: information
about AI risks, ways to take action, and tools for volunteers and organizers.

**English:** <https://pauseai.ca> · **Français:** <https://pauseia.ca>

Both domains serve the same application.

## What people can do

- Answer three questions and explore suggested readings about AI risks, a pause
  in development, and international coordination.
- Read campaign updates, protest reports, press releases, and the movement's
  strategy.
- Create an account to save resources, keep track of actions, and find their
  member of Parliament.
- Prepare a message to their MP through the Warning Shot campaign.
- Subscribe to updates or pledge a one-time or monthly contribution. Pledges
  record an intention to give; the site does not collect payments yet.

## Organizing and administration

Authorized organizers can create accounts individually or in batches by pasting
spreadsheet rows or uploading CSV files. They can assign a group for the batch,
override it for an individual row, save drafts, review the recipients, and send
invitations. Account management includes group assignments and recorded email
history, with access limited by role and group.

Superadmins can review donation pledges and site activity. Browser-visit totals
use Toronto calendar days; signed-in superadmins and explicitly excluded
browsers do not count. These are browser-visit measurements, not a count of people.

## Stack

- Elixir 1.20.2 / Erlang OTP 29
- Phoenix 1.8 and Phoenix LiveView 1.2
- PostgreSQL 18
- Tailwind CSS 4 through Phoenix's Tailwind integration

Exact package versions are recorded in [`mix.lock`](mix.lock).

## Local development

Install Elixir, Erlang, and PostgreSQL, then:

```bash
mix setup
mix phx.server
```

Open <http://localhost:4013>. The French-domain entry point is
<http://pauseia.localhost:4013>. Development email is captured locally at
<http://localhost:4013/dev/mailbox>.

The development server listens on all interfaces, so you can also open
`http://<your-machine>:4013` from a phone or tablet on the same network. Set
`PORT` to use a different port.

Before proposing a change:

```bash
mix precommit
```

Browser acceptance tests additionally need Node.js 22 and Playwright's Chromium
browser. Run the suite with:

```bash
mix test.atdd
```

Use a separate `MIX_TEST_PARTITION` and `ATDD_PORT` when running concurrent
checkouts. Development and test mail must remain isolated from live delivery.

## Acceptance-test harness

The shared [AcceptanceHarness repository on GitHub](https://github.com/ogourment/acceptance_harness)
is a public code mirror containing the harness implementation and documentation.
The website pins its dependency in `mix.exs` and `mix.lock`. Acceptance evidence
records completed journeys and visible coverage gaps; an unfinished journey is
not reported as passed.

## Privacy

Questionnaire answers are kept in browser storage and associated with a random
first-party browser identifier for learning metrics. Learning visits, resource
opens, and bookmarks use that identifier. Signing in associates those signals
with the account to reduce double-counting. Account action records are private
to their owner. Browser-visit counts store daily aggregates without retaining
IP addresses or user agents.

See the [privacy policy](https://pauseai.ca/en/privacy) for data handling,
service providers, and choices. The website application and its database are
hosted in Canada.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development and editorial guidance.
Contributions can include clearer wording, translations, source corrections,
accessibility improvements, and code.
