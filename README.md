# PauseAI Canada website

A bilingual information and organizing platform for PauseAI Canada.

The first product loop helps a visitor:

1. reflect on AI existential risk, pausing, and international coordination;
2. receive a transparent reading suggestion stored only in their browser;
3. explore reviewed English and French source material;
4. create an account;
5. keep a private log of actions they have taken.

## Stack

- Elixir 1.20.2 / Erlang OTP 29
- Phoenix 1.8.9
- Phoenix LiveView 1.2.8
- PostgreSQL 18
- Tailwind CSS 4 through Phoenix's Tailwind integration

Exact package versions are recorded in `mix.lock`.

## Local development

Install Elixir, Erlang, and PostgreSQL, then:

```bash
mix setup
mix phx.server
```

Visit <http://localhost:4013>. Development email is available at
<http://localhost:4013/dev/mailbox>.

The development server listens on all interfaces, so you can also open
`http://<your-machine>:4013` from a phone or tablet on the same network. Set
`PORT` to use a different port.

Before proposing a change:

```bash
mix precommit
```

## Privacy boundary

Anonymous onboarding answers use browser `localStorage`. They are not sent to
the Phoenix application. Account action records are private to their owner.
Account data is stored by the application and governed by the published privacy
policy. Deployment, retention, backup, and incident-response requirements are
documented in the private operating guide.

## Human contribution workflow

This repository deliberately contains no committed `AGENTS.md` or `CLAUDE.md`.
It can be understood, developed, tested, and reviewed with ordinary human
tools. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Content

Initial cards summarize and link to material from
[PauseAI](https://pauseai.info/), [Pause IA](https://pauseia.fr/fr), and the
movement-strategy article that motivates the organizing path. Material is
linked and summarized rather than copied.

## Status

The current release is deployed to staging and production at
`pauseai.ca`.
