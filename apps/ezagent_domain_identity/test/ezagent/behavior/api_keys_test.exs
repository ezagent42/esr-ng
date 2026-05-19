defmodule Ezagent.Behavior.ApiKeysTest do
  use ExUnit.Case, async: true

  alias Ezagent.Behavior.ApiKeys

  describe "init_slice/1" do
    test "starts with empty keys map" do
      assert ApiKeys.init_slice(%{}) == %{keys: %{}}
    end
  end

  describe "invoke(:put_api_key, ...)" do
    test "adds a key" do
      slice = ApiKeys.init_slice(%{})
      args = %{provider: "deepseek", key: "sk-1234567890abcdef"}

      assert {:ok, new_slice, %{ok: true, provider: "deepseek"}} =
               ApiKeys.invoke(:put_api_key, slice, args, %{})

      assert new_slice.keys == %{"deepseek" => "sk-1234567890abcdef"}
    end

    test "overwrites existing key for the same provider (rotation)" do
      slice = %{keys: %{"deepseek" => "sk-old-key-xxxx"}}
      args = %{provider: "deepseek", key: "sk-new-key-yyyy"}

      assert {:ok, new_slice, _} = ApiKeys.invoke(:put_api_key, slice, args, %{})
      assert new_slice.keys["deepseek"] == "sk-new-key-yyyy"
    end
  end

  describe "invoke(:list_api_keys, ...)" do
    test "returns masked keys, sorted by provider" do
      slice = %{
        keys: %{
          "openai" => "sk-aaaabbbbccccdddd",
          "deepseek" => "sk-1234567890abcdef"
        }
      }

      assert {:ok, _slice, %{api_keys: listing}} = ApiKeys.invoke(:list_api_keys, slice, %{}, %{})
      providers = Enum.map(listing, & &1.provider)
      assert providers == ["deepseek", "openai"]

      [first, _second] = listing
      assert first.provider == "deepseek"
      assert first.masked == "sk-1234...cdef"
      refute String.contains?(first.masked, "567890abc")
    end

    test "empty slice returns empty list" do
      assert {:ok, _, %{api_keys: []}} =
               ApiKeys.invoke(:list_api_keys, ApiKeys.init_slice(%{}), %{}, %{})
    end
  end

  describe "invoke(:delete_api_key, ...)" do
    test "removes the provider entry" do
      slice = %{keys: %{"deepseek" => "sk-x"}}

      assert {:ok, new_slice, %{ok: true}} =
               ApiKeys.invoke(:delete_api_key, slice, %{provider: "deepseek"}, %{})

      assert new_slice.keys == %{}
    end

    test "deleting a non-existent provider is a no-op" do
      slice = %{keys: %{}}

      assert {:ok, ^slice, %{ok: true}} =
               ApiKeys.invoke(:delete_api_key, slice, %{provider: "ghost"}, %{})
    end
  end

  describe "invoke(:get_api_key, ...)" do
    test "returns the plaintext for a registered provider" do
      slice = %{keys: %{"deepseek" => "sk-1234567890abcdef"}}

      assert {:ok, _slice, %{key: "sk-1234567890abcdef", provider: "deepseek"}} =
               ApiKeys.invoke(:get_api_key, slice, %{provider: "deepseek"}, %{})
    end

    test "errors for an unknown provider" do
      slice = ApiKeys.init_slice(%{})

      assert {:error, {:no_api_key, "missing"}} =
               ApiKeys.invoke(:get_api_key, slice, %{provider: "missing"}, %{})
    end
  end

  describe "mask/1" do
    test "sk-prefixed key shows first 4 + last 4" do
      assert ApiKeys.mask("sk-1234567890abcdef") == "sk-1234...cdef"
    end

    test "non-sk key still gets first 4 + last 4" do
      assert ApiKeys.mask("abcdefghij1234567890") == "abcd...7890"
    end

    test "short keys collapse to ***" do
      assert ApiKeys.mask("short") == "***"
    end
  end
end
