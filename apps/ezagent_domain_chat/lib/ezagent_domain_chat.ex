defmodule EzagentDomainChat do
  @moduledoc """
  Top-level facade for the chat plugin (Phase 3b-step 1).

  Provides `create_session/2` to dynamically spawn additional Session
  Kinds at runtime (admin LV / mix task / external API / first-login
  wizard can call this).

  ## PR-J (Phase 8c, Allen 2026-05-20)

  The previous `:main_is_static` restriction was removed. `session://main`
  is no longer a hardcoded static supervisor child of
  `EzagentDomainChat.Application` — it now goes through the same code
  path as every other session, created by the first-login wizard. The
  test environment seeds it via this same facade in
  `EzagentDomainChat.Application` (test-only branch).

  `create_session/2` is the canonical session-creation API: it spawns
  the Kind, binds it to the default workspace (workspace contract
  invariant), and joins the creator. Idempotent for same short_name —
  re-call returns the existing URI + (re)joins creator.
  """

  alias Ezagent.{Invocation, KindRegistry}
  alias Ezagent.Entity.{Session, User}

  @doc """
  Spawn a new Session Kind at `session://<short_name>` under
  `EzagentDomainChat.SessionSupervisor`, bind it to the default
  workspace, and join `creator_uri` to it.

  Returns `{:ok, session_uri}` on success, `{:error, reason}` on:
  - `{:already_registered, _}` — session URI already in KindRegistry
  - other DynamicSupervisor errors propagated as-is

  Idempotent re-spawn of same short_name returns `{:ok, existing_uri}`
  (via `{:already_started, pid}` → reuse pid).
  """
  @spec create_session(String.t(), URI.t() | nil) :: {:ok, URI.t()} | {:error, term()}
  def create_session(short_name, creator_uri \\ nil)

  def create_session(short_name, creator_uri) when is_binary(short_name) and short_name != "" do
    session_uri = URI.new!("session://#{short_name}")
    spec = {Ezagent.Kind.Server, {Session, %{uri: session_uri}}}

    result = DynamicSupervisor.start_child(EzagentDomainChat.SessionSupervisor, spec)

    case result do
      {:ok, _pid} ->
        :ok = bind_default_workspace(session_uri)
        :ok = join_creator(session_uri, creator_uri || User.admin_uri())
        {:ok, session_uri}

      # `:already_started` = same child spec already in supervisor's children
      # `:already_registered` = Kind.Server.init crashed on KindRegistry.put_new
      # conflict (URI claimed by another pid, possibly outside this supervisor).
      # Both indicate "session exists" — return success + re-bind workspace
      # (idempotent ETS overwrite) + re-attempt join (cast is idempotent on
      # members map).
      {:error, {:already_started, _pid}} ->
        :ok = bind_default_workspace(session_uri)
        :ok = join_creator(session_uri, creator_uri || User.admin_uri())
        {:ok, session_uri}

      {:error, {:already_registered, _}} ->
        :ok = bind_default_workspace(session_uri)
        :ok = join_creator(session_uri, creator_uri || User.admin_uri())
        {:ok, session_uri}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_session(_short_name, _creator), do: {:error, :short_name_required}

  @doc """
  Return all known Session URIs (KindRegistry session:// entries),
  including main + all dynamically-created sessions. Used by LV
  sidebar render.
  """
  @spec list_sessions :: [URI.t()]
  def list_sessions do
    KindRegistry.list_all()
    |> Enum.filter(fn {uri_str, _pid} -> String.starts_with?(uri_str, "session://") end)
    |> Enum.map(fn {uri_str, _pid} -> URI.new!(uri_str) end)
    |> Enum.sort_by(&URI.to_string/1)
  end

  # PR-J — bind every session to a workspace at creation. Closes the
  # invariant (`sessions_have_workspace_test.exs`) for sessions created
  # via this facade. Uses the canonical default workspace URI from
  # `Ezagent.WorkspaceRegistry.default_workspace_uri/0`. Idempotent
  # ETS write — re-binding is a no-op overwrite.
  defp bind_default_workspace(session_uri) do
    {:ok, workspace_uri} = Ezagent.WorkspaceRegistry.default_workspace_uri()
    Ezagent.WorkspaceRegistry.bind(session_uri, workspace_uri)
  end

  defp join_creator(session_uri, creator_uri) do
    # PR-M (Allen 2026-05-20) — `chat.join` requires the member's Kind
    # alive in KindRegistry (see Behavior.Chat.invoke(:join) — returns
    # `{:error, {:member_not_registered, _}}` if absent). In production
    # the login path already calls `Ezagent.Entity.ensure_spawned/1`
    # before the wizard reaches create_session. For mix tasks /
    # boot-time test seeds, the test-env admin Kind seed in
    # `EzagentDomainIdentity.Application` covers admin. Demand-spawn
    # any non-admin caller here as belt-and-suspenders — idempotent
    # ({:ok, pid} for already-alive).
    _ = Ezagent.SpawnRegistry.spawn(creator_uri)

    target = URI.new!("#{URI.to_string(session_uri)}?action=chat.join")

    _ =
      Invocation.dispatch(%Invocation{
        target: target,
        mode: :cast,
        args: %{member: creator_uri},
        ctx: %{
          caller: creator_uri,
          caps: User.admin_caps(),
          reply: :ignore
        }
      })

    :ok
  end
end
