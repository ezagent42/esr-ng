defmodule Esr.Routing.RuleStoreTest do
  use ExUnit.Case
  alias Esr.Routing.{Matcher, RuleStore}
  alias EsrCore.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  # PR 9 §A: DefaultRules.bootstrap seeds a system_default rule into
  # MentionRouting at chat plugin boot. Tests that assert specific row
  # counts must filter to admin-source rows.
  defp admin_rules(table) do
    RuleStore.list(table)
    |> Enum.reject(&(&1.source == RuleStore.system_default_source()))
  end

  test "add → list round-trip with matcher JSON encoded" do
    table = EsrDomainChat.Routing.MentionRouting

    {:ok, row} =
      RuleStore.add(
        table,
        Matcher.text_contains("urgent"),
        ["session://oncall"],
        URI.new!("user://admin")
      )

    assert row.table_name == Atom.to_string(table)
    assert row.matcher_data == %{"type" => "text_contains", "arg" => "urgent"}
    assert row.receivers == ["session://oncall"]
    assert row.created_by == "user://admin"

    [loaded] = admin_rules(table)
    assert loaded.id == row.id
    assert {:ok, _matcher} = Matcher.from_json(loaded.matcher_data)
  end

  test "list scoped by table name — other tables don't leak" do
    {:ok, _} =
      RuleStore.add(
        EsrDomainChat.Routing.MentionRouting,
        Matcher.always(),
        ["session://a"],
        nil
      )

    {:ok, _} =
      RuleStore.add(
        EsrDomainChat.Routing.SessionRouting,
        Matcher.from("agent://x"),
        ["session://b"],
        nil
      )

    assert length(admin_rules(EsrDomainChat.Routing.MentionRouting)) == 1
    assert length(admin_rules(EsrDomainChat.Routing.SessionRouting)) == 1
  end

  test "delete removes by id" do
    {:ok, row} =
      RuleStore.add(EsrDomainChat.Routing.MentionRouting, Matcher.always(), ["session://x"], nil)

    assert :ok = RuleStore.delete(row.id)
    assert {:error, :not_found} = RuleStore.delete(row.id)
    assert [] = admin_rules(EsrDomainChat.Routing.MentionRouting)
  end

  test "URI struct receiver gets serialized to string" do
    {:ok, row} =
      RuleStore.add(
        EsrDomainChat.Routing.MentionRouting,
        Matcher.always(),
        [URI.new!("session://x"), URI.new!("session://y")],
        URI.new!("user://admin")
      )

    assert row.receivers == ["session://x", "session://y"]
  end
end
