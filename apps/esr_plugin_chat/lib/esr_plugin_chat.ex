defmodule EsrPluginChat do
  @moduledoc """
  Top-level facade for the chat plugin (Phase 3b-step 1).

  Provides `create_session/2` to dynamically spawn additional Session
  Kinds at runtime (admin LV / mix task / external API can call this).

  Per #B4: `session://main` is a static child of `EsrPluginChat.Application`
  (boot-time). Only **non-main** sessions go through this facade.
  Calling `create_session/2` with `"main"` short-name returns
  `{:error, :main_is_static}` to surface the constraint.
  """

  alias Esr.{Invocation, KindRegistry}
  alias Esr.Entity.{Session, User}

  @doc """
  Spawn a new Session Kind at `session://<short_name>` under
  `EsrPluginChat.SessionSupervisor` and join `creator_uri` to it.

  Returns `{:ok, session_uri}` on success, `{:error, reason}` on:
  - `:main_is_static` — short_name == "main" (use static child instead)
  - `{:already_registered, _}` — session URI already in KindRegistry
  - other DynamicSupervisor errors propagated as-is

  Idempotent re-spawn of same short_name returns `{:ok, existing_uri}`
  (via `{:already_started, pid}` → reuse pid).
  """
  @spec create_session(String.t(), URI.t() | nil) :: {:ok, URI.t()} | {:error, term()}
  def create_session(short_name, creator_uri \\ nil)

  def create_session("main", _creator), do: {:error, :main_is_static}

  def create_session(short_name, creator_uri) when is_binary(short_name) do
    session_uri = URI.new!("session://#{short_name}")
    spec = {Esr.Kind.Server, {Session, %{uri: session_uri}}}

    case DynamicSupervisor.start_child(EsrPluginChat.SessionSupervisor, spec) do
      {:ok, _pid} ->
        :ok = join_creator(session_uri, creator_uri || User.admin_uri())
        {:ok, session_uri}

      # `:already_started` = same child spec already in supervisor's children
      # `:already_registered` = Kind.Server.init crashed on KindRegistry.put_new
      # conflict (URI claimed by another pid, possibly outside this supervisor).
      # Both indicate "session exists" — return success + re-attempt join (cast
      # is idempotent on members map).
      {:error, {:already_started, _pid}} ->
        :ok = join_creator(session_uri, creator_uri || User.admin_uri())
        {:ok, session_uri}

      {:error, {:already_registered, _}} ->
        :ok = join_creator(session_uri, creator_uri || User.admin_uri())
        {:ok, session_uri}

      {:error, reason} ->
        {:error, reason}
    end
  end

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

  defp join_creator(session_uri, creator_uri) do
    target = URI.new!("#{URI.to_string(session_uri)}/behavior/chat/join")

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
