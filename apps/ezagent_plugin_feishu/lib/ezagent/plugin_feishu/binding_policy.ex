defmodule EzagentPluginFeishu.BindingPolicy do
  @moduledoc """
  Phase 6 PR 15 — what happens when a Feishu open_id gets bound to a
  local user.

  Today: grant the local user a Capability that authorizes any
  dispatch into the `feishu_chat://*` Kind family — i.e. they can
  send text / image / file / future-card / etc. to any Feishu chat
  the bot is in.

  ## Where to extend

  Adding more "default permissions on bind" (e.g. read-only access
  to a Feishu approval workflow, ability to schedule a Feishu poll)
  is done HERE — a new `grant_<feature>_cap/2` private + a call from
  `apply/2`. Other code paths (transport, storage, send API) don't
  need to know about each new grant.

  ## Why a separate module from UserBinding

  `UserBinding` is pure storage; `BindingPolicy` is side-effects on
  state change. Keeping them apart means tests for storage don't
  exercise dispatch, and tests for policy can stub the store. Future
  multi-policy support (per-workspace defaults, role templates)
  swaps `apply/2` without touching storage.
  """

  alias Ezagent.{Capability, Invocation}

  @doc """
  Apply binding side-effects: grants the standard cap set to
  `user_uri`. Idempotent — re-bind won't double-grant (MapSet
  semantics in Identity slice).

  `admin_uri` = the operator who authorized the bind (for granted_by
  attribution + dispatch ctx).
  """
  @spec apply(URI.t() | String.t(), URI.t() | String.t()) :: :ok | {:error, term()}
  def apply(user_uri, admin_uri) do
    with :ok <- ensure_user_kind(user_uri),
         :ok <- ensure_user_default_caps(user_uri, admin_uri) do
      grant_feishu_send_cap(user_uri, admin_uri)
    end
  end

  # Bound user might not be live yet (admin types `mix ezagent.feishu.bind
  # ou_xxx user://newcomer` for a brand-new user). Auto-spawn via
  # SpawnRegistry so the cap dispatch has a target.
  defp ensure_user_kind(user_uri) do
    uri = to_uri(user_uri)

    case Ezagent.KindRegistry.lookup(uri) do
      {:ok, _pid} ->
        :ok

      :error ->
        case Ezagent.SpawnRegistry.spawn(uri) do
          {:ok, _pid} -> :ok
          err -> err
        end
    end
  end

  defp grant_feishu_send_cap(user_uri, admin_uri) do
    grant_cap(
      user_uri,
      admin_uri,
      %Capability{
        kind: :feishu_chat,
        behavior: :any,
        instance: :any,
        granted_by: to_uri(admin_uri),
        granted_at: DateTime.utc_now()
      }
    )
  end

  # PR 27 (Allen 2026-05-18): users created before this PR (or via
  # programmatic spawn paths that bypass `Ezagent.Domain.Identity.Users.create`)
  # might not have the default user caps installed. When we bind a
  # Feishu identity to them, top up the default caps so the bound
  # user can actually act as a delegate. Identity slice uses MapSet
  # semantics so this is idempotent — already-granted caps don't
  # double-up.
  #
  # The caps themselves come from `Ezagent.Entity.User.default_caps/0` —
  # this module doesn't know what "default" means, it only ensures the
  # baseline is applied.
  defp ensure_user_default_caps(user_uri, admin_uri) do
    Ezagent.Entity.User.default_caps()
    |> Enum.reduce_while(:ok, fn cap, _acc ->
      case grant_cap(user_uri, admin_uri, cap) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp grant_cap(user_uri, admin_uri, %Capability{} = cap) do
    target = URI.new!("#{to_str(user_uri)}/behavior/identity/grant_cap")

    inv = %Invocation{
      target: target,
      mode: :call,
      args: %{cap: cap},
      ctx: %{
        caller: to_uri(admin_uri),
        caps: Ezagent.Entity.User.admin_caps(),
        reply: :sync
      }
    }

    case Invocation.dispatch(inv) do
      {:ok, _} -> :ok
      :ok -> :ok
      err -> err
    end
  end

  defp to_uri(%URI{} = u), do: u
  defp to_uri(s) when is_binary(s), do: URI.parse(s)

  defp to_str(%URI{} = u), do: URI.to_string(u)
  defp to_str(s) when is_binary(s), do: s
end
