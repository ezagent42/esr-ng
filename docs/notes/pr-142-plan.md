# PR #142 — Entity-agnostic three-piece (S-1, S-2, S-3)

Implements proposals S-1, S-2, S-3 from `entity-agnostic-architecture-reflection.md` §4. Prerequisite: PR #141 (scheme migration to entity://) merged.

## S-1 — `Ezagent.Entity.authenticate(uri, secret)`

New facade module `apps/ezagent_core/lib/ezagent/entity.ex`:

```elixir
defmodule Ezagent.Entity do
  @moduledoc """
  Entity facade — entity-agnostic auth + identity helpers.

  Today every dispatch surface (login form, CLI bearer-token, future
  agent-driven /admin) needs to "verify this URI presented this
  secret and return its caps". Before SPEC v2 this was split:
  `user://` URIs went through bcrypt against `users.password_hash`;
  `agent://` URIs had no equivalent (they were spawned by capability,
  no separate auth step).

  After PR #142, `entity://` is the unified scheme; this module is
  the unified auth path.
  """

  @spec authenticate(URI.t(), String.t()) ::
          {:ok, %{caps: MapSet.t(Ezagent.Capability.t())}} | {:error, term()}
  def authenticate(%URI{scheme: "entity", host: "user", path: "/" <> name}, password)
      when is_binary(password) do
    # bcrypt path (existing Ezagent.Domain.Identity.Users.verify_password/2)
    case Ezagent.Users.verify_password("entity://user/#{name}", password) do
      {:ok, _user} ->
        caps = Ezagent.Identity.list_caps_for(URI.parse("entity://user/#{name}"))
        {:ok, %{caps: caps}}
      err -> err
    end
  end

  def authenticate(%URI{scheme: "entity", host: "agent"} = uri, token) when is_binary(token) do
    # bearer-token path against entity_tokens table (see S-2)
    Ezagent.Entity.Token.verify(uri, token)
  end

  def authenticate(uri, _), do: {:error, {:unsupported_entity_uri, uri}}
end
```

Replace direct `Users.verify_password/2` calls in `SessionController.create/2` with `Entity.authenticate/2`. Login form accepts `entity://user/<name>` or `entity://agent/<flavor>_<name>` URIs.

## S-2 — `entity_tokens` table

New Ecto schema + migration:

```sql
CREATE TABLE entity_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_uri TEXT NOT NULL,         -- entity://user/X or entity://agent/Y_Z
  token_hash TEXT NOT NULL,         -- bcrypt(token)
  label TEXT,                       -- operator-readable name (e.g. "cli-laptop")
  created_at TEXT NOT NULL,
  expires_at TEXT,                  -- nullable (no-expiry tokens for agents)
  last_used_at TEXT
);
CREATE INDEX entity_tokens_entity_uri ON entity_tokens (entity_uri);
```

New module `Ezagent.Entity.Token`:

```elixir
defmodule Ezagent.Entity.Token do
  @doc "Mint a fresh token for entity_uri. Returns {plain_token, %EntityToken{}}."
  def mint(entity_uri, opts \\ [])
  
  @doc "Verify a presented token against entity_uri. Updates last_used_at on match."
  def verify(entity_uri, token)
  
  @doc "Revoke a token by id (operator action)."
  def revoke(token_id)
  
  @doc "List tokens for entity_uri (without plain token — only metadata)."
  def list(entity_uri)
end
```

Migrate existing `users.cli_token` rows to entity_tokens (1 row per non-null cli_token, label=`migrated-cli`). Drop `users.cli_token` column.

Update CLI auth path: token verification goes through `Entity.Token.verify/2` instead of `Users.lookup_by_cli_token/1`.

## S-3 — `current_user_uri` → `current_entity_uri` rename

Files touching `current_user_uri` (likely ~15-25 files):

- `apps/ezagent_web/lib/ezagent_web/plugs/require_user.ex` → rename module to `RequireEntity` + assign key
- `apps/ezagent_web/lib/ezagent_web/live_auth.ex` → assign key
- `apps/ezagent_web/lib/ezagent_web/controllers/session_controller.ex` → session cookie key + assigns
- `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/*_live.ex` → reads of `socket.assigns.current_user_uri`
- All test fixtures that build conns with `Plug.Test.init_test_session(%{"current_user_uri" => ...})`

The rename is mechanical. Mass-edit via sed-style approach.

Plug renaming: `EzagentWeb.Plugs.RequireUser` → `EzagentWeb.Plugs.RequireEntity` (module rename; one `plug :require_entity` callsite in router.ex).

Session cookie key: `"current_user_uri"` → `"current_entity_uri"`. This is a breaking change for existing sessions; clean rebuild handles it.

## Verification

- All 12 app test suites pass
- Login form accepts `entity://user/admin` + bcrypt password → routes to /admin
- Login form rejects `entity://agent/cc_X` with bcrypt password (wrong auth type) — but accepts with bearer token
- CLI tool can present a token for `entity://agent/<flavor>_<name>` and get its caps
- Existing `mix ezagent.user.set_password user://admin --password X` task continues to work (input format flexibility — accept both, canonicalize)

## Scope (this PR only)

DO:
- Entity facade module
- entity_tokens table + Token module
- current_user_uri rename across all surfaces
- Plug.RequireUser → Plug.RequireEntity rename
- Session cookie key rename
- Update SessionController + LiveAuth + tests
- Drop users.cli_token column

DO NOT:
- Delete feishu:// scheme (PR #143)
- Delete synthetic singletons (PR #144)
- @known_schemes runtime ETS (PR #145)
- Query-string action syntax (PR #146)
- AgentTypeRegistry deletion + Message.uri rename (PR #147)

## Estimated effort

Smaller than PR #141 — most files just change identifier names. Subagent ~45-90 min.
