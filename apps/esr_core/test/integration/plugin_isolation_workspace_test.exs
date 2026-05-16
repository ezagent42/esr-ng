defmodule Esr.Integration.PluginIsolationWorkspaceTest do
  @moduledoc """
  # Phase 4 north-star invariant test

  Per memory `feedback_completion_requires_invariant_test`:
  Phase 4 cannot be declared done on merge + tests-pass alone — there
  must be a test that fails when the architectural goal is unmet.

  **The goal**: future plugin authors add new Kinds without
  coordinating with core (and core never references plugin code).

  **The proof**: a fake Kind defined here in test/ (NOT in esr_core/lib/,
  NOT in any plugin/lib/) — registered at runtime via
  `Esr.SpawnRegistry` — is declared as a member of a persisted
  Workspace, the Workspace is torn down + reloaded, and the fake Kind
  comes back alive WITHOUT esr_core or any plugin needing to know
  about it ahead of time.

  If this test breaks, plugin isolation is broken — investigate before
  shipping.

  ## What's verified

  1. A new URI scheme (`probe`) can be registered at runtime via
     `Esr.SpawnRegistry.register/2`
  2. A Workspace declaring `probe://X` as a member can be persisted
     via `Esr.Workspace.create/2`
  3. Killing the Workspace + its declared members simulates a node
     restart's "everything gone" state
  4. `Esr.Workspace.Loader.load_all/0` re-spawns the fake Kind
     from persisted state, using the runtime-registered spawn fn

  esr_core never references `ProbeKind`, `ProbeBehavior`, or
  `:probe`. The test enforces this by defining them in this module
  (not in `lib/`).
  """

  use EsrCore.DataCase, async: false

  alias Esr.{KindRegistry, SpawnRegistry, Workspace}

  # ---------------------------------------------------------------
  # Fake plugin types — defined inline in the test, NOT in lib/
  # ---------------------------------------------------------------

  defmodule ProbeBehavior do
    @behaviour Esr.Behavior

    @impl true
    def actions, do: [:ping]

    @impl true
    def state_slice, do: :probe

    @impl true
    def init_slice(_args), do: %{pings: 0}

    @impl true
    def invoke(:ping, slice, _args, _ctx) do
      {:ok, %{slice | pings: slice.pings + 1}, %{pong: true}}
    end

    @impl true
    def interface,
      do: %{ping: %{args: %{}, returns: %{pong: :boolean}, modes: [:call]}}
  end

  defmodule ProbeKind do
    @behaviour Esr.Kind

    @impl true
    def type_name, do: :probe

    @impl true
    def behaviors, do: [ProbeBehavior]

    @impl true
    def persistence, do: :ephemeral

    @impl true
    def uri_from_args(args), do: Map.fetch!(args, :uri)
  end

  # ---------------------------------------------------------------
  # The invariant
  # ---------------------------------------------------------------

  test "PHASE 4 INVARIANT: plugin-defined Kind survives Workspace teardown + Loader rehydrate" do
    # 1. Plugin-author work: declare a new URI scheme + register spawn fn.
    #    This is what a future plugin's Application.start would do.
    probe_uri = URI.parse("probe://invariant-#{System.unique_integer([:positive])}")

    SpawnRegistry.register("probe", fn uri ->
      DynamicSupervisor.start_child(
        Esr.Workspace.Supervisor,
        {Esr.Kind.Server, {ProbeKind, %{uri: uri}}}
      )
    end)

    # 2. Plugin-author work: persist a Workspace declaring the probe as a member.
    workspace_name = "invariant-#{System.unique_integer([:positive])}"
    {:ok, _pid} = Workspace.create(workspace_name, %{members: [probe_uri]})

    # Sanity: probe is not yet alive (create/2 only persists + spawns the
    # Workspace Kind itself; member spawning happens via Loader).
    assert :error = KindRegistry.lookup(probe_uri)

    # 3. Run the Loader — this is what happens at app start. It should
    #    walk every persisted Workspace, dispatch :instantiate, and call
    #    SpawnRegistry for each declared child.
    results = Esr.Workspace.Loader.load_all()

    # Find our workspace in the results
    {^workspace_name, children_results} =
      Enum.find(results, fn {name, _} -> name == workspace_name end)

    assert [{^probe_uri, {:ok, probe_pid}}] = children_results
    assert is_pid(probe_pid)
    assert Process.alive?(probe_pid)

    # 4. The probe is now in KindRegistry under its URI — Loader truly
    #    re-spawned it from persisted Workspace state.
    assert {:ok, ^probe_pid} = KindRegistry.lookup(probe_uri)

    # 5. Tear down: terminate via DynamicSupervisor so it doesn't auto-restart.
    #    (Process.exit would cause :one_for_one to immediately re-spawn,
    #    which is the wrong simulation — we want "node went down".)
    workspace_uri = Esr.Entity.Workspace.uri_for(workspace_name)
    {:ok, workspace_pid} = KindRegistry.lookup(workspace_uri)

    :ok = DynamicSupervisor.terminate_child(Esr.Workspace.Supervisor, probe_pid)
    :ok = DynamicSupervisor.terminate_child(Esr.Workspace.Supervisor, workspace_pid)

    # Wait briefly for Registry cleanup (Registry monitors its keys)
    wait_until(fn -> KindRegistry.lookup(probe_uri) == :error end)
    wait_until(fn -> KindRegistry.lookup(workspace_uri) == :error end)

    # 6. The proof: Loader.load_all/0 re-runs and the probe is alive again
    #    — purely from persisted state + runtime-registered spawn fn,
    #    no esr_core / plugin code knows about :probe.
    _ = Esr.Workspace.Loader.load_all()

    assert {:ok, new_probe_pid} = KindRegistry.lookup(probe_uri)
    assert is_pid(new_probe_pid)
    assert Process.alive?(new_probe_pid)
    refute new_probe_pid == probe_pid
  end

  defp wait_until(fun, attempts \\ 50)
  defp wait_until(_fun, 0), do: flunk("wait_until: condition never became true")

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end
end
