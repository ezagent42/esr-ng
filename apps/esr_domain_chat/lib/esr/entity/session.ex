defmodule Esr.Entity.Session do
  @moduledoc """
  Session Kind — the "room" in Phase 2's chat routing model.

  A Session is the entity that holds a set of member URIs and routes
  outbound chat messages to them. Per Decision #61 + P2-D2 K-path:
  Session handles `:send / :join / :leave` actions; the member-side
  `:receive` action runs on the recipient Kind (User / Agent).

  Phase 2 spawns exactly one default instance — `session://main` —
  at `EsrDomainChat.Application.start/2`. Multi-Session support is
  intentionally out of scope (Phase 3+).

  ## Persistence flipped to {:snapshot, :on_change} in Phase 7 PR 44

  Phase 2 originally used `:ephemeral` — members / monitors /
  last_seen were rebuilt at each boot from PubSub re-announcements
  and admin User re-join in `handle_continue(:announce_ready)`.
  Historical message stream was persisted (via `Esr.MessageStore`);
  only in-flight membership was ephemeral.

  **Phase 7 PR 44 (D7-7 + SPEC §7-3 working-copy session slice)**:
  the orchestrator's `template_working_copy` field on Chat slice
  (Session-context) must survive phx restart so the orchestrator's
  team-refinement work isn't lost on every server bounce. Flipping
  persistence to `{:snapshot, :on_change}` makes the Chat slice's
  `template_working_copy` durable. Pre-Phase-7 sessions reload
  with empty working_copy on next state change → behaves as before.

  Members / monitors / last_seen ARE now persisted as a side
  effect of the slice-level snapshot. This is mostly harmless:
  members get re-validated when their owning Kind comes up (admin
  User, Agents via bridge re-announce); monitors are stale across
  restart anyway (refs only valid for live processes); last_seen
  reflects history not live state. The added durability is mostly
  invisible to existing flows.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :session

  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.Chat]

  @impl Esr.Kind
  # Phase 7 PR 44: WILL FLIP TO {:snapshot, :on_change} once orchestrator
  # working-copy lands (PR 46). Phase 7 PR 44 explored the flip and
  # discovered it triggers snapshot writes during tests that don't
  # own the Ecto sandbox connection (Esr.Audit.Writer-style cascade
  # via Esr.Kind.Snapshot.save_now). Fix is per-test setup updates,
  # not a code revert. Deferred to PR 46 which adds the
  # template_working_copy slice field AND the test-helper updates
  # together. Until then, persistence stays :ephemeral — working-copy
  # is lost on restart, accepted in dev / acceptable for v1 demo.
  def persistence, do: :ephemeral

  @doc "URI of the default Session instance spawned at boot."
  @spec default_uri() :: URI.t()
  def default_uri, do: URI.new!("session://main")
end
