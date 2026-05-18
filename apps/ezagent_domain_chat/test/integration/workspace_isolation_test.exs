defmodule EzagentDomainChat.Integration.WorkspaceIsolationTest do
  @moduledoc """
  Phase 7 PR 31 invariant — workspace_uri-scoped routing rules
  must NOT fire for messages dispatched in a different workspace.

  Drives the **production path**: `Chat.invoke(:send, ...)` at
  chat.ex:116 → `Resolver.resolve/4` with `workspace_uri:` opt
  derived from `WorkspaceRegistry.lookup(session_uri)`. Pre-PR-31
  this call used 3-arg `resolve/3` with empty opts, silently
  dropping the workspace scope.

  Receipts are observed via the audit log (`invocations` table)
  rather than recipient slice state — recipients (User Kind) may
  just PubSub.broadcast for LV consumption with no DB write, so
  audit is the authoritative cross-recipient observable.

  V criteria gated (per VERIFICATION.md):
  - V3.2 — Workspace isolation enforced at CapBAC + Resolver
  - V4.4 — Workspace-scoped routing CI gate
  """

  use EzagentCore.DataCase, async: false
  import Ecto.Query

  alias Ezagent.{Invocation, Message, RoutingRegistry}
  alias Ezagent.Routing.{Matcher, RuleStore}
  alias Ezagent.Entity.User

  setup do
    original = Application.get_env(:ezagent_core, :routing_tables)

    on_exit(fn ->
      if original do
        Application.put_env(:ezagent_core, :routing_tables, original)
      else
        Application.delete_env(:ezagent_core, :routing_tables)
      end
    end)

    :ok
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp setup_scenario do
    suffix = unique("ws-iso")
    table_name = String.to_atom("workspace_iso_test_#{suffix}")
    :ok = RoutingRegistry.declare_table(table_name, key_uniqueness: :duplicate)
    Application.put_env(:ezagent_core, :routing_tables, [table_name])

    workspace_a = URI.new!("workspace://#{suffix}-A")
    workspace_b = URI.new!("workspace://#{suffix}-B")

    session_a = URI.new!("session://#{suffix}-A-main")
    session_b = URI.new!("session://#{suffix}-B-main")

    {:ok, _} = Ezagent.SpawnRegistry.spawn(session_a)
    {:ok, _} = Ezagent.SpawnRegistry.spawn(session_b)

    :ok = Ezagent.WorkspaceRegistry.bind(session_a, workspace_a)
    :ok = Ezagent.WorkspaceRegistry.bind(session_b, workspace_b)

    sender = URI.new!("user://#{unique("sender")}")
    eavesdropper = URI.new!("user://#{unique("eavesdropper")}")

    {:ok, _} = Ezagent.SpawnRegistry.spawn(sender)
    {:ok, _} = Ezagent.SpawnRegistry.spawn(eavesdropper)

    %{
      table: table_name,
      workspace_a: workspace_a,
      workspace_b: workspace_b,
      session_a: session_a,
      session_b: session_b,
      sender: sender,
      eavesdropper: eavesdropper
    }
  end

  defp dispatch_send(session_uri, sender, text) do
    msg = Message.new(sender, %{text: text, attachments: []})

    inv = %Invocation{
      target: URI.new!("#{URI.to_string(session_uri)}/behavior/chat/send"),
      mode: :cast,
      args: %{message: msg},
      ctx: %{caller: sender, caps: User.admin_caps(), reply: :ignore}
    }

    Invocation.dispatch(inv)
    # Audit writes are async (Ezagent.Audit.Writer flushes ~every 1s).
    # Force a flush so this test doesn't race the writer.
    if Process.whereis(Ezagent.Audit.Writer), do: send(Ezagent.Audit.Writer, :flush)
    Process.sleep(250)
    msg
  end

  defp receive_dispatches_to(target_uri) do
    target_prefix = "#{URI.to_string(target_uri)}/behavior/chat/receive"

    EzagentCore.Repo.all(
      from(i in "invocations",
        where:
          fragment("? LIKE ?", i.target, ^"#{target_prefix}%") and
            i.authz == "granted",
        select: i.inserted_at
      )
    )
  end

  test "rule scoped to workspace://A does NOT fire for message dispatched in workspace://B" do
    ctx = setup_scenario()

    {:ok, _} =
      RuleStore.add(
        ctx.table,
        Matcher.always(),
        [URI.to_string(ctx.eavesdropper)],
        URI.to_string(User.admin_uri()),
        workspace_uri: URI.to_string(ctx.workspace_a)
      )

    :ok = RuleStore.load_into_registry(ctx.table)

    eavesdropper_before = length(receive_dispatches_to(ctx.eavesdropper))

    _msg_b = dispatch_send(ctx.session_b, ctx.sender, "in workspace B")

    eavesdropper_after = length(receive_dispatches_to(ctx.eavesdropper))

    assert eavesdropper_after == eavesdropper_before,
           "workspace-A-scoped rule fired for workspace-B message " <>
             "(eavesdropper received #{eavesdropper_after - eavesdropper_before} unexpected dispatch) — " <>
             "PR 31 workspace isolation broken"
  end

  test "rule scoped to workspace://A DOES fire for message dispatched in workspace://A (positive control)" do
    ctx = setup_scenario()

    {:ok, _} =
      RuleStore.add(
        ctx.table,
        Matcher.always(),
        [URI.to_string(ctx.eavesdropper)],
        URI.to_string(User.admin_uri()),
        workspace_uri: URI.to_string(ctx.workspace_a)
      )

    :ok = RuleStore.load_into_registry(ctx.table)

    eavesdropper_before = length(receive_dispatches_to(ctx.eavesdropper))

    _msg_a = dispatch_send(ctx.session_a, ctx.sender, "in workspace A")

    eavesdropper_after = length(receive_dispatches_to(ctx.eavesdropper))

    assert eavesdropper_after > eavesdropper_before,
           "workspace-A-scoped rule did NOT fire for workspace-A message — " <>
             "the scoping mechanism dropped a valid match (false negative)"
  end

  test "nil-scoped (global) rule fires for messages in any workspace (regression guard)" do
    ctx = setup_scenario()

    {:ok, _} =
      RuleStore.add(
        ctx.table,
        Matcher.always(),
        [URI.to_string(ctx.eavesdropper)],
        URI.to_string(User.admin_uri()),
        workspace_uri: nil
      )

    :ok = RuleStore.load_into_registry(ctx.table)

    eavesdropper_before = length(receive_dispatches_to(ctx.eavesdropper))

    _ = dispatch_send(ctx.session_a, ctx.sender, "from A — global rule should fire")
    _ = dispatch_send(ctx.session_b, ctx.sender, "from B — global rule should fire")

    eavesdropper_after = length(receive_dispatches_to(ctx.eavesdropper))

    assert eavesdropper_after - eavesdropper_before >= 2,
           "nil-scoped (global) rule did not fire for both workspaces — " <>
             "regression in pre-PR-31 behavior (workspace_uri scoping broke global rules)"
  end

  test "unbound session (no WorkspaceRegistry entry) falls back to global semantics" do
    ctx = setup_scenario()

    suffix = unique("unbound")
    session_unbound = URI.new!("session://#{suffix}-unbound")
    {:ok, _} = Ezagent.SpawnRegistry.spawn(session_unbound)
    # deliberately NO WorkspaceRegistry.bind for this session

    {:ok, _} =
      RuleStore.add(
        ctx.table,
        Matcher.always(),
        [URI.to_string(ctx.eavesdropper)],
        URI.to_string(User.admin_uri()),
        workspace_uri: nil
      )

    :ok = RuleStore.load_into_registry(ctx.table)

    eavesdropper_before = length(receive_dispatches_to(ctx.eavesdropper))

    _ = dispatch_send(session_unbound, ctx.sender, "from unbound session")

    eavesdropper_after = length(receive_dispatches_to(ctx.eavesdropper))

    assert eavesdropper_after > eavesdropper_before,
           "unbound session lookup raised an error that prevented dispatch — " <>
             "WorkspaceRegistry.lookup :error must transparently fall back to nil scope " <>
             "(preserves pre-PR-31 behavior for legacy snapshots)"
  end
end
