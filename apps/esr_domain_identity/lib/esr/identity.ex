defmodule Esr.Identity do
  @moduledoc """
  Facade for reading Identity slice (caps) per principal URI.

  Phase 4-completion Spec 05 §A.2.3: LV mounts call `list_caps_for/1`
  to derive `ctx.caps` from the session cookie's `current_user_uri`.

  Uses the dispatch path so cap checks fire naturally (and audit rows
  appear for non-admin reads). Per Q-MU-5 default: every spawned User
  gets a self-grant cap (`%Capability{kind: :user, behavior: Identity,
  instance: own_uri}`) automatically in `init_slice`, so freshly logged-in
  users CAN read their own caps via dispatch without bypassing auth.
  """

  alias Esr.{Invocation, KindRegistry}

  @doc """
  List capabilities held by `principal_uri`. Returns `MapSet.t(Capability.t())`.

  Falls back to `MapSet.new()` if the User Kind isn't spawned yet
  (boot-window or unprovisioned user).
  """
  @spec list_caps_for(URI.t() | String.t()) :: MapSet.t(Esr.Capability.t())
  def list_caps_for(uri) do
    user_uri = parse_uri(uri)

    case KindRegistry.lookup(user_uri) do
      :error ->
        MapSet.new()

      {:ok, _pid} ->
        target = URI.parse("#{URI.to_string(user_uri)}/behavior/identity/list_caps")

        case Invocation.dispatch(%Invocation{
               target: target,
               mode: :call,
               args: %{},
               ctx: %{
                 caller: user_uri,
                 caps: bootstrap_self_cap(user_uri),
                 reply: {:caller_inbox, self()}
               }
             }) do
          {:ok, %{caps: caps}} when is_list(caps) -> MapSet.new(caps)
          _ -> MapSet.new()
        end
    end
  end

  # Caller's own list_caps cap — per Q-MU-5 default. This is the
  # "self-grant" needed to dispatch list_caps_for one's own URI without
  # already having external caps. Since admin's caps include :any/:any/:any,
  # this matters only for non-admin first-mount.
  defp bootstrap_self_cap(user_uri) do
    MapSet.new([
      %Esr.Capability{
        kind: :user,
        behavior: Esr.Behavior.Identity,
        instance: user_uri,
        granted_by: URI.parse("system://bootstrap"),
        granted_at: ~U[2026-01-01 00:00:00Z]
      }
    ])
  end

  defp parse_uri(%URI{} = u), do: u
  defp parse_uri(s) when is_binary(s), do: URI.parse(s)
end
