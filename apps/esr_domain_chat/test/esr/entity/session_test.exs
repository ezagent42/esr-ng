defmodule Esr.Entity.SessionTest do
  use ExUnit.Case, async: true
  alias Esr.Entity.Session

  describe "Esr.Kind contract" do
    test "type_name/0 returns :session" do
      assert Session.type_name() == :session
    end

    test "behaviors/0 returns [Esr.Behavior.Chat]" do
      assert Session.behaviors() == [Esr.Behavior.Chat]
    end

    test "persistence/0 is :ephemeral (Phase 7 PR 44 explored flip, deferred to PR 46)" do
      # Phase 7 PR 44 attempted to flip to {:snapshot, :on_change}
      # for orchestrator working-copy durability (SPEC §7-3) but the
      # snapshot writes cascade through tests that don't own the
      # Ecto sandbox connection — test-helper update is required
      # before the flip. Deferred to PR 46 (orchestrator tools)
      # which adds the slice field AND the helper updates together.
      # Esr.Entity.Session moduledoc documents the planned flip.
      assert Session.persistence() == :ephemeral
    end
  end

  describe "default_uri/0" do
    test "returns session://main as a %URI{} struct" do
      uri = Session.default_uri()
      assert %URI{scheme: "session", host: "main"} = uri
    end
  end
end
