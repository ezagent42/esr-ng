defmodule Ezagent.Routing.MatcherCombinatorsTest do
  use ExUnit.Case, async: true

  alias Ezagent.Routing.Matcher

  defp msg(text \\ "hello", mentions \\ [], sender \\ "user://admin") do
    %Ezagent.Message{
      uri: "message://test",
      sender: URI.parse(sender),
      body: %{text: text, attachments: []},
      mentions: Enum.map(mentions, &URI.parse/1),
      ref: nil,
      inserted_at: ~U[2026-05-16 00:00:00.000000Z]
    }
  end

  describe "all_of/1 + match?/2" do
    test "true when every leaf matches" do
      m = Matcher.all_of([Matcher.mention("agent://x"), Matcher.text_contains("hi")])
      assert Matcher.match?(m, msg("hi all", ["agent://x"]))
    end

    test "false when any leaf fails" do
      m = Matcher.all_of([Matcher.mention("agent://x"), Matcher.text_contains("never")])
      refute Matcher.match?(m, msg("hi", ["agent://x"]))
    end

    test "empty list is vacuously true" do
      assert Matcher.match?(Matcher.all_of([]), msg())
    end
  end

  describe "any_of/1 + match?/2" do
    test "true when at least one leaf matches" do
      m = Matcher.any_of([Matcher.from("user://admin"), Matcher.text_contains("never")])
      assert Matcher.match?(m, msg("hi", [], "user://admin"))
    end

    test "false when no leaf matches" do
      m = Matcher.any_of([Matcher.text_contains("never"), Matcher.from("user://other")])
      refute Matcher.match?(m, msg("hi", [], "user://admin"))
    end

    test "empty list is vacuously false" do
      refute Matcher.match?(Matcher.any_of([]), msg())
    end
  end

  describe "negate/1 + match?/2" do
    test "flips leaf result" do
      assert Matcher.match?(Matcher.negate(Matcher.text_contains("never")), msg("hi"))
      refute Matcher.match?(Matcher.negate(Matcher.text_contains("hi")), msg("hi"))
    end

    test "double negation cancels" do
      assert Matcher.match?(
               Matcher.negate(Matcher.negate(Matcher.text_contains("hi"))),
               msg("hi")
             )
    end
  end

  describe "nested combinators" do
    test "and(or(mention X, mention Y), not from Z)" do
      m =
        Matcher.all_of([
          Matcher.any_of([Matcher.mention("agent://x"), Matcher.mention("agent://y")]),
          Matcher.negate(Matcher.from("user://blocked"))
        ])

      assert Matcher.match?(m, msg("hi", ["agent://y"], "user://admin"))
      refute Matcher.match?(m, msg("hi", ["agent://y"], "user://blocked"))
      refute Matcher.match?(m, msg("hi", ["agent://z"], "user://admin"))
    end
  end

  describe "JSON serde for combinators" do
    test "and round-trip" do
      m = Matcher.all_of([Matcher.mention("agent://x"), Matcher.from("user://admin")])
      assert {:ok, ^m} = m |> Matcher.to_json() |> Matcher.from_json()
    end

    test "or round-trip" do
      m = Matcher.any_of([Matcher.text_contains("urgent"), Matcher.always()])
      assert {:ok, ^m} = m |> Matcher.to_json() |> Matcher.from_json()
    end

    test "not round-trip" do
      m = Matcher.negate(Matcher.from("user://blocked"))
      assert {:ok, ^m} = m |> Matcher.to_json() |> Matcher.from_json()
    end

    test "deeply nested round-trip" do
      m =
        Matcher.all_of([
          Matcher.any_of([Matcher.mention("agent://x"), Matcher.mention("agent://y")]),
          Matcher.negate(Matcher.from("user://blocked")),
          Matcher.text_matches("^/help")
        ])

      assert {:ok, ^m} = m |> Matcher.to_json() |> Matcher.from_json()
    end
  end

  describe "backward compat" do
    test "existing leaf-only JSON still decodes" do
      assert {:ok, {:mention, "user://admin"}} =
               Matcher.from_json(%{"type" => "mention", "arg" => "user://admin"})
    end
  end
end
