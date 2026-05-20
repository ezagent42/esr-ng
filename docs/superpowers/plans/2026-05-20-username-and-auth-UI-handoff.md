# Username & Auth — UI handoff to Phase 8

The **backend** for Username & Auth is complete on branch
`worktree-username-and-auth` (opened as a PR against `main`, **not yet
merged** — see the PR link provided alongside this doc). It ships three
new tables + facade modules, the mailer/rate-limiter infra, and the
controller-rendered auth pages. **The admin LiveView UI was intentionally
left to you** (the Phase 8 IDE Shell effort) because Phase 8 rewrites
every admin LV and already has `settings_live.ex` / `profile_live.ex` /
`identities_live.ex`.

## How to take it over

1. **Merge the Username & Auth backend PR.** It bases on `main`. If `main`
   has moved, **you do the rebase** — the backend is all new domain
   modules + new controllers + 3 new migrations, so conflicts should be
   minimal (the only shared touch-points are `config/config.exs`,
   `apps/ezagent_web/mix.exs`, `mix.lock`, `apps/ezagent_web/lib/ezagent_web/router.ex`,
   `apps/ezagent_web/lib/ezagent_web/application.ex`).
2. Then wire the UI below, following the `UI / Frontend Contract` in the
   `ezagent-developer` skill (atoms, Tailwind tokens, `dark:` variants,
   no inline styles).

## Backend interfaces now available

- `Ezagent.EntityPresenter.display/1` — friendly name for one URI (profile
  `display_name`, else the URI path segment).
- `Ezagent.EntityPresenter.display_many/1` — batch version, returns
  `%{uri_string => name}`. **Use this for any list/table** (member panels,
  message history, entity lists) — one query, not one per row.
- `Ezagent.Entity.Profile.get/1` · `by_email/1` · `upsert/1` — read/write a
  profile (`%{entity_uri, display_name, email}`). `upsert/1` returns
  `{:ok, profile}` or `{:error, changeset}` (email-uniqueness violation).
- `Ezagent.AppSettings.get/1` · `put/2` · `smtp_configured?/0` — runtime
  config. Keys: `"smtp_config"` (map with `host/port/username/password/
  from_address/tls`), `"registration_domains"` (list of strings).

Data model: `entity_profiles(entity_uri PK, display_name, email)`,
`app_settings(key PK, value JSON)`.

## UI to build

1. **Display names everywhere a URI is shown to a human.** In the rewritten
   member panel / conversation view / entities (identities) list / users list
   / admin shell — render `EntityPresenter.display(uri)` as the primary label,
   keep the raw URI as a secondary monospace line where useful. For lists,
   batch with `display_many/1` at mount/refresh — never call `display/1`
   per row. `@mention` pickers: show + filter by `display_name`, keep the
   URI as the option value.

2. **Display-name editing.** In the users list (or `profile_live.ex`): an
   inline field that calls
   `Ezagent.Entity.Profile.upsert(%{entity_uri: uri, display_name: name})`.
   `display_name` is freely mutable; the URI is NOT (immutable primary key).

3. **Bare-handle input.** The create-user form should accept a bare handle
   (`allen`) and prepend `entity://user/` before submit.

4. **SMTP + registration settings page** (`settings_live.ex`). Admin-only.
   - SMTP form: host / port / username / password / from_address / tls →
     `AppSettings.put("smtp_config", %{...})`. Password field MUST mask and
     never echo the stored value.
   - Registration-domains editor → `AppSettings.put("registration_domains",
     ["company.com", ...])`. Empty list = no self-registration.
   - "Send test email" button → `EzagentWeb.Mailer.deliver_magic_link(
     admin_email, test_url)`; surface `{:ok, _}` / `{:error, reason}`.
   - Show `AppSettings.smtp_configured?()` as a status indicator.

## Do NOT touch

The controller-rendered auth pages — `/login`, `/login/credentials`,
`/auth/magic/:token`, `/register/complete` — are done and live in
`SessionController` / `MagicLinkController` / `RegistrationController`. They
are auth-boundary pages (self-contained `<style>`, exempt from the contract).

## Why it matters

Until the SMTP settings page exists, email login is inert in production
(SMTP can only be set via `iex`). The settings page is what activates the
whole feature.
