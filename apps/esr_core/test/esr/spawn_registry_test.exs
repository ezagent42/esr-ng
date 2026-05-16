defmodule Esr.SpawnRegistryTest do
  use ExUnit.Case, async: false

  alias Esr.SpawnRegistry

  describe "register/2 + spawn/1" do
    test "registered spawn fn is invoked for matching scheme" do
      test_pid = self()
      scheme = "spawnreg-test-#{System.unique_integer([:positive])}"

      SpawnRegistry.register(scheme, fn uri ->
        send(test_pid, {:spawn_called, uri})
        {:ok, self()}
      end)

      uri = URI.parse("#{scheme}://x")
      assert {:ok, _pid} = SpawnRegistry.spawn(uri)
      assert_receive {:spawn_called, ^uri}
    end

    test "unknown scheme returns {:error, {:no_spawn_fn, scheme}}" do
      uri = URI.parse("nonesuch-scheme-#{System.unique_integer([:positive])}://x")
      assert {:error, {:no_spawn_fn, _}} = SpawnRegistry.spawn(uri)
    end

    test "spawn/1 returns existing pid if URI already registered in KindRegistry" do
      # Use admin user — guaranteed alive in test env via chat plugin Application
      uri = Esr.Entity.User.admin_uri()
      {:ok, existing_pid} = Esr.KindRegistry.lookup(uri)

      # Even though no "user" spawn fn might be registered (it is via chat
      # plugin, but doesn't matter here), the KindRegistry lookup short-
      # circuits before consulting SpawnRegistry.
      assert {:ok, ^existing_pid} = SpawnRegistry.spawn(uri)
    end

    test "registered_schemes/0 lists every registered scheme" do
      scheme = "list-test-#{System.unique_integer([:positive])}"
      SpawnRegistry.register(scheme, fn _ -> {:ok, self()} end)

      assert scheme in SpawnRegistry.registered_schemes()
    end
  end

  describe "{:already_started, pid} translation" do
    test "spawn/1 unwraps :already_started to {:ok, pid}" do
      scheme = "already-test-#{System.unique_integer([:positive])}"
      fake_pid = spawn(fn -> :timer.sleep(:infinity) end)

      SpawnRegistry.register(scheme, fn _uri -> {:error, {:already_started, fake_pid}} end)

      uri = URI.parse("#{scheme}://x")
      assert {:ok, ^fake_pid} = SpawnRegistry.spawn(uri)
    end
  end
end
