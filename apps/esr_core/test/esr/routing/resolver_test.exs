defmodule Esr.Routing.ResolverTest do
  use ExUnit.Case, async: false
  alias Esr.{Message, RoutingRegistry}
  alias Esr.Routing.{Matcher, Resolver}

  # Resolver hard-codes the table names per spec (P3-D impl Resolver-Matcher
  # interface decision (b)): EsrPluginChat.Routing.MentionRouting +
  # EsrPluginChat.Routing.SessionRouting. We declare them in tests and let
  # the live RoutingRegistry hold our test data.
  @mention_table EsrPluginChat.Routing.MentionRouting
  @session_table EsrPluginChat.Routing.SessionRouting

  setup do
    # Clean ETS slate per test — declare_table is idempotent for same caller,
    # but values from prior tests would leak. Use a fresh process to scope
    # ownership.
    cleanup_routing_tables()

    # Declare in this test process so it owns the tables for this test.
    :ok = RoutingRegistry.declare_table(@mention_table, key_uniqueness: :duplicate)
    :ok = RoutingRegistry.declare_table(@session_table)

    on_exit(fn -> cleanup_routing_tables() end)

    :ok
  end

  defp cleanup_routing_tables do
    for t <- [@mention_table, @session_table] do
      data = :"esr_routing_#{t}"
      reverse = :"esr_routing_reverse_#{t}"

      for table <- [data, reverse] do
        try do
          :ets.delete(table)
        catch
          :error, :badarg -> :ok
        end
      end

      try do
        :ets.delete(:esr_routing_registry_meta, t)
      catch
        _, _ -> :ok
      end
    end
  end

  defp msg(text \\ "hello", mentions \\ []) do
    Message.new(URI.new!("user://admin"), %{text: text, attachments: []}, mentions: mentions)
  end

  describe "resolve/2" do
    test "returns [] when no rule matches → caller falls through to in-session default" do
      assert [] = Resolver.resolve(msg(), URI.new!("session://main"))
    end

    test "mention(X) rule fires when message mentions X — returns receivers" do
      target = URI.new!("agent://cc-builder")

      # rule: mention(cc-builder) → [session://oncall]
      :ok =
        RoutingRegistry.put(
          @mention_table,
          Matcher.mention(target),
          ["session://oncall"]
        )

      result = Resolver.resolve(msg("hi", [target]), URI.new!("session://main"))
      assert result == [URI.new!("session://oncall")]
    end

    test "additive: multiple rules matching → union receivers, deduplicated" do
      target = URI.new!("agent://X")

      # 2 rules both match — receivers union
      :ok =
        RoutingRegistry.put(
          @mention_table,
          Matcher.mention(target),
          ["session://A", "session://B"]
        )

      :ok =
        RoutingRegistry.put(
          @mention_table,
          Matcher.always(),
          ["session://B", "session://C"]
        )

      result = Resolver.resolve(msg("hi", [target]), URI.new!("session://main"))
      uris = result |> Enum.map(&URI.to_string/1) |> Enum.sort()
      assert uris == ["session://A", "session://B", "session://C"]
    end

    test "text_contains rule matches body" do
      :ok =
        RoutingRegistry.put(
          @mention_table,
          Matcher.text_contains("urgent"),
          ["session://oncall"]
        )

      assert Resolver.resolve(msg("server urgent down"), URI.new!("session://main")) ==
               [URI.new!("session://oncall")]

      # No match if word absent
      assert Resolver.resolve(msg("all green"), URI.new!("session://main")) == []
    end

    test "table not declared (e.g. in stripped-down test env) → silently skip" do
      # Tear down the mention table mid-test
      cleanup_routing_tables()

      # Resolver doesn't crash, returns []
      assert [] = Resolver.resolve(msg(), URI.new!("session://main"))
    end
  end
end
