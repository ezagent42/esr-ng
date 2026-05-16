defmodule Esr.RoutingRegistryTest do
  @moduledoc """
  Phase 3a-step 1: RoutingRegistry contract tests.

  Each test declares its own uniquely-named table (the calling process
  becomes owner). Tables die with the test process — no cross-test
  pollution.
  """

  use ExUnit.Case, async: false
  alias Esr.RoutingRegistry

  defp unique_table(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  describe "declare_table/2" do
    test "unique table accepts put_new + reject same key twice" do
      t = unique_table(:test_unique)
      :ok = RoutingRegistry.declare_table(t)

      assert :ok = RoutingRegistry.put_new(t, "key1", "value1")
      assert {:error, :already_set} = RoutingRegistry.put_new(t, "key1", "value2")
      assert {:ok, "value1"} = RoutingRegistry.lookup(t, "key1")
    end

    test "duplicate table accepts multiple values per key via put/3" do
      t = unique_table(:test_dup)
      :ok = RoutingRegistry.declare_table(t, key_uniqueness: :duplicate)

      :ok = RoutingRegistry.put(t, "k", "v1")
      :ok = RoutingRegistry.put(t, "k", "v2")
      :ok = RoutingRegistry.put(t, "k", "v3")

      assert MapSet.new(RoutingRegistry.lookup_all(t, "k")) == MapSet.new(["v1", "v2", "v3"])
    end

    test "put_new on :duplicate table raises (use put/3)" do
      t = unique_table(:test_dup_putnew)
      :ok = RoutingRegistry.declare_table(t, key_uniqueness: :duplicate)

      assert_raise ArgumentError, fn ->
        RoutingRegistry.put_new(t, "k", "v")
      end
    end

    test "re-declaring with same owner is no-op" do
      t = unique_table(:test_redeclare)
      :ok = RoutingRegistry.declare_table(t)
      assert :ok = RoutingRegistry.declare_table(t)
    end

    test "re-declaring with different owner raises" do
      t = unique_table(:test_redeclare_other)
      :ok = RoutingRegistry.declare_table(t)

      # Use spawn + receive to avoid the linked-Task killing this process
      parent = self()
      spawn(fn ->
        result =
          try do
            RoutingRegistry.declare_table(t)
            :unexpected_ok
          rescue
            e in ArgumentError -> {:raised, e.message}
          end

        send(parent, {:result, result})
      end)

      assert_receive {:result, {:raised, msg}}, 500
      assert msg =~ "already declared by"
    end
  end

  describe "lookup variants" do
    test "lookup returns :error for missing key" do
      t = unique_table(:test_miss)
      :ok = RoutingRegistry.declare_table(t)
      assert :error = RoutingRegistry.lookup(t, "absent")
    end

    test "lookup_all returns [] for missing key" do
      t = unique_table(:test_miss_all)
      :ok = RoutingRegistry.declare_table(t)
      assert [] = RoutingRegistry.lookup_all(t, "absent")
    end

    test "list_all returns all pairs" do
      t = unique_table(:test_list)
      :ok = RoutingRegistry.declare_table(t, key_uniqueness: :duplicate)

      :ok = RoutingRegistry.put(t, "a", 1)
      :ok = RoutingRegistry.put(t, "b", 2)
      :ok = RoutingRegistry.put(t, "a", 3)

      assert MapSet.new(RoutingRegistry.list_all(t)) ==
               MapSet.new([{"a", 1}, {"b", 2}, {"a", 3}])
    end
  end

  describe "owner-only write" do
    test "non-owner put fails with :not_owner" do
      t = unique_table(:test_nonowner)
      :ok = RoutingRegistry.declare_table(t)

      task =
        Task.async(fn ->
          RoutingRegistry.put(t, "k", "v")
        end)

      assert {:error, {:not_owner, _}} = Task.await(task)
    end
  end

  describe "reverse_index" do
    test "reverse_index returns keys for a value when enabled" do
      t = unique_table(:test_rev)
      :ok = RoutingRegistry.declare_table(t, reverse_index: true)

      :ok = RoutingRegistry.put_new(t, "k1", "shared")
      :ok = RoutingRegistry.put_new(t, "k2", "shared")
      :ok = RoutingRegistry.put_new(t, "k3", "other")

      assert MapSet.new(RoutingRegistry.reverse_index(t, "shared")) == MapSet.new(["k1", "k2"])
      assert RoutingRegistry.reverse_index(t, "other") == ["k3"]
    end

    test "reverse_index raises when not enabled" do
      t = unique_table(:test_norev)
      :ok = RoutingRegistry.declare_table(t)

      assert_raise ArgumentError, fn ->
        RoutingRegistry.reverse_index(t, "anything")
      end
    end
  end

  describe "errors on undeclared table" do
    test "lookup on undeclared table raises (table doesn't exist)" do
      t = unique_table(:test_undecl)

      assert_raise ArgumentError, fn ->
        RoutingRegistry.put(t, "k", "v")
      end
    end
  end
end
