defmodule Mix.Tasks.Ezagent.Plugin.InstallTest do
  @moduledoc """
  Phase 7 PR 36 invariant — `mix ezagent.plugin.install` exists and
  documents its D7-8 contract (Plugin unload deferred,
  `Mix.env()` compile-time pitfall noted).

  Pure structural checks. Behavioral tests for actual plugin
  hot-loading require a tmp Mix project fixture (toy plugin
  compiled in isolation) — deferred to Phase 7-4 manual smoke
  test + plugin authoring guide examples (PR 51).
  """

  use ExUnit.Case, async: true

  test "Mix.Tasks.Ezagent.Plugin.Install module exists with run/1" do
    Code.ensure_loaded(Mix.Tasks.Ezagent.Plugin.Install)

    assert function_exported?(Mix.Tasks.Ezagent.Plugin.Install, :run, 1),
           "expected run/1 to be defined on Mix.Tasks.Ezagent.Plugin.Install"
  end

  test "moduledoc covers the D7-8 contract surface" do
    source =
      File.read!(Path.join(__DIR__, "../../../lib/mix/tasks/ezagent.plugin.install.ex"))

    assert source =~ "D7-8",
           "moduledoc should reference D7-8 (the Decision Log entry this task closes)"

    assert source =~ "Plugin unload",
           "moduledoc should explicitly call out that uninstall is deferred " <>
             "(prevents future dev from assuming the symmetric task exists)"

    assert source =~ ~r/Mix\.env\(\)/,
           "moduledoc should warn about the Mix.env() compile-time pitfall " <>
             "(plugin authors must know this trap)"

    assert source =~ "ensure_all_started",
           "moduledoc should document the actual mechanism (ensure_all_started)"
  end

  test "non-existent application load returns error (the path the task's error branch handles)" do
    fake_app = :"phase_7_test_nonexistent_#{System.unique_integer([:positive])}"

    result = :application.load(fake_app)

    case result do
      {:error, _reason} ->
        :ok

      :ok ->
        flunk(
          "loading a non-existent app #{inspect(fake_app)} unexpectedly succeeded — " <>
            "the install task's error path won't fire"
        )
    end
  end
end
