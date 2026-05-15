defmodule Esr.Entity.Session do
  @moduledoc """
  Session Kind — the "room" in Phase 2's chat routing model.

  A Session is the entity that holds a set of member URIs and routes
  outbound chat messages to them. Per Decision #61 + P2-D2 K-path:
  Session handles `:send / :join / :leave` actions; the member-side
  `:receive` action runs on the recipient Kind (User / Agent).

  Phase 2 spawns exactly one default instance — `session://main` —
  at `EsrPluginChat.Application.start/2`. Multi-Session support is
  intentionally out of scope (Phase 3+).

  ## Why ephemeral

  Phase 2 doesn't persist session state across restarts — members /
  monitors / last_seen are rebuilt at each boot (admin User rejoins
  in `handle_continue(:announce_ready)`; agents rejoin when their
  bridge reconnects). The historical message stream IS persisted
  (via `Esr.MessageStore`); only the in-flight membership is
  ephemeral. Phase 3+ will add `{:snapshot, :on_change}` if we need
  Session metadata (name, created_at, etc) to survive restarts.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :session

  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.Chat]

  @impl Esr.Kind
  def persistence, do: :ephemeral

  @doc "URI of the default Session instance spawned at boot."
  @spec default_uri() :: URI.t()
  def default_uri, do: URI.new!("session://main")
end
