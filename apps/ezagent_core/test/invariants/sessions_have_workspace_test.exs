defmodule EzagentCore.Invariants.SessionsHaveWorkspaceTest do
  @moduledoc """
  Phase 8c PR-E (Allen 2026-05-20) — architectural invariant test.

  Every live session in `Ezagent.KindRegistry` must have a binding in
  `Ezagent.WorkspaceRegistry`. The architecture treats workspace as
  the deployment unit for sessions; an orphan session breaks
  workspace-scoped routing, snapshot grouping, and the upcoming UI
  workspace-name display.

  ## How the invariant was broken historically

  `session://main` (Phase 2 seed) was started as a static supervisor
  child of `EzagentDomainChat.Application` (line 80) which bypasses
  `Ezagent.Entity.Session.spawn_from_template/2` — the proper API
  that calls `WorkspaceRegistry.bind/2`. The bypass was grandfathered
  in by all subsequent phases. PR-E added an explicit
  `bind_default_session_to_default_workspace/0` post-boot step to
  close the gap. This test ensures no future static child or other
  bypass re-introduces the issue.

  ## How to fix a failing test

  If you add a new session via any path that doesn't go through
  `Session.spawn_from_template/2`, you MUST also call
  `Ezagent.WorkspaceRegistry.bind(session_uri, workspace_uri)`
  before this test fires. The canonical default is
  `Ezagent.WorkspaceRegistry.default_workspace_uri/0`.
  """
  use ExUnit.Case, async: false

  alias Ezagent.{KindRegistry, WorkspaceRegistry}

  test "every session in KindRegistry has a WorkspaceRegistry binding" do
    sessions =
      KindRegistry.list_all()
      |> Enum.filter(fn entry ->
        uri = entry_uri(entry)
        uri != nil and URI.parse(uri).scheme == "session"
      end)

    orphans =
      sessions
      |> Enum.reject(fn entry ->
        uri = entry_uri(entry)
        match?({:ok, %URI{}}, WorkspaceRegistry.lookup(uri))
      end)
      |> Enum.map(&entry_uri/1)

    assert orphans == [],
           """
           Orphan sessions (no WorkspaceRegistry binding):
           #{Enum.map_join(orphans, "\n  ", &"- #{&1}")}

           Every session must call `Ezagent.WorkspaceRegistry.bind/2`
           after spawn — see `EzagentDomainChat.Application.bind_default_session_to_default_workspace/0`
           for the canonical pattern. Default workspace is
           `Ezagent.WorkspaceRegistry.default_workspace_uri/0`.
           """
  end

  # KindRegistry entries are tuples — extract URI string regardless of shape.
  defp entry_uri({uri, _kind_module, _pid}) when is_binary(uri), do: uri
  defp entry_uri({uri, _kind_module}) when is_binary(uri), do: uri
  defp entry_uri(%{uri: uri}) when is_binary(uri), do: uri
  defp entry_uri(uri) when is_binary(uri), do: uri
  defp entry_uri(_), do: nil
end
