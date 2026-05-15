defmodule Esr.URITest do
  use ExUnit.Case, async: true

  describe "parse!/1" do
    test "parses agent:// URI" do
      uri = Esr.URI.parse!("agent://allen-builder")
      assert uri.scheme == "agent"
      assert uri.host == "allen-builder"
    end

    test "parses URI with behavior path" do
      uri = Esr.URI.parse!("agent://echo/behavior/echo/say")
      assert uri.scheme == "agent"
      assert uri.host == "echo"
      assert uri.path == "/behavior/echo/say"
    end

    test "raises on missing scheme" do
      assert_raise ArgumentError, ~r/missing scheme/, fn ->
        Esr.URI.parse!("/no-scheme")
      end
    end

    test "raises on unknown scheme" do
      assert_raise ArgumentError, ~r/not in known set/, fn ->
        Esr.URI.parse!("http://example.com")
      end
    end
  end

  describe "instance/1" do
    test "drops path/query/fragment" do
      uri = Esr.URI.parse!("agent://echo/behavior/echo/say")
      inst = Esr.URI.instance(uri)
      assert inst.scheme == "agent"
      assert inst.host == "echo"
      assert inst.path == nil
      assert URI.to_string(inst) == "agent://echo"
    end

    test "instance of an already-instance URI is itself" do
      uri = Esr.URI.parse!("user://admin")
      assert Esr.URI.instance(uri) == uri
    end
  end

  describe "behavior_action/1" do
    test "extracts {behavior_atom, action_atom}" do
      uri = Esr.URI.parse!("agent://echo/behavior/echo/say")
      assert {:ok, {:echo, :say}} = Esr.URI.behavior_action(uri)
    end

    test "returns :malformed_path for non-behavior paths" do
      uri = Esr.URI.parse!("agent://echo")
      assert {:error, :malformed_path} = Esr.URI.behavior_action(uri)
    end

    test "returns :malformed_path for short paths" do
      uri = Esr.URI.parse!("agent://echo/random/thing")
      assert {:error, :malformed_path} = Esr.URI.behavior_action(uri)
    end
  end
end
