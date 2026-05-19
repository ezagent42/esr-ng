defmodule Ezagent.AgentTypeRegistryTest do
  use ExUnit.Case, async: false

  alias Ezagent.AgentTypeRegistry

  setup do
    AgentTypeRegistry.init()

    # Clean slate for each test — wipe any registrations our test made
    # (other plugins' real registrations stay; tests use unique flavor names).
    :ok
  end

  describe "register/2 + registered_flavors/0" do
    test "registers a flavor and exposes it via registered_flavors" do
      flavor = "test-flavor-#{System.unique_integer([:positive])}"

      :ok =
        AgentTypeRegistry.register(flavor, fn _uri, name ->
          send(self(), {:spawned, name})
          {:ok, self()}
        end)

      assert flavor in AgentTypeRegistry.registered_flavors()
    end
  end

  describe "spawn/1 — dispatch by entity://agent/<flavor>_<name> prefix" do
    test "calls the registered fn with the URI + full name" do
      flavor = "deldist#{System.unique_integer([:positive])}"
      this = self()

      :ok =
        AgentTypeRegistry.register(flavor, fn uri, name ->
          send(this, {:dispatched, uri, name})
          {:ok, this}
        end)

      uri = URI.new!("entity://agent/#{flavor}_the-name")
      assert {:ok, ^this} = AgentTypeRegistry.spawn(uri)
      assert_receive {:dispatched, ^uri, name}, 200
      # Per task spec: full name string (flavor prefix + tail) passes through
      assert name == "#{flavor}_the-name"
    end

    test "rejects URI without flavor prefix" do
      assert {:error, {:missing_flavor_prefix, "no-underscore"}} =
               AgentTypeRegistry.spawn(URI.new!("entity://agent/no-underscore"))
    end

    test "rejects unknown flavor" do
      assert {:error, {:unknown_agent_flavor, "made-up-flavor-xyz"}} =
               AgentTypeRegistry.spawn(URI.new!("entity://agent/made-up-flavor-xyz_x"))
    end

    test "rejects non-entity scheme" do
      assert {:error, {:not_agent_entity_uri, "session://main"}} =
               AgentTypeRegistry.spawn(URI.new!("session://main"))
    end

    test "rejects entity://user/X (wrong host)" do
      assert {:error, {:not_agent_entity_uri, "entity://user/admin"}} =
               AgentTypeRegistry.spawn(URI.new!("entity://user/admin"))
    end

    test "passes through {:already_started, pid} as success" do
      flavor = "alread#{System.unique_integer([:positive])}"
      target_pid = spawn(fn -> Process.sleep(:infinity) end)

      :ok =
        AgentTypeRegistry.register(flavor, fn _uri, _name ->
          {:error, {:already_started, target_pid}}
        end)

      assert {:ok, ^target_pid} =
               AgentTypeRegistry.spawn(URI.new!("entity://agent/#{flavor}_x"))
    end
  end

  describe "validate_uri/1 — strict shape check" do
    setup do
      flavor = "validatest#{System.unique_integer([:positive])}"
      :ok = AgentTypeRegistry.register(flavor, fn _uri, _name -> {:ok, self()} end)
      {:ok, flavor: flavor}
    end

    test "accepts entity://agent/<flavor>_<name> for a registered flavor", %{flavor: flavor} do
      assert :ok = AgentTypeRegistry.validate_uri("entity://agent/#{flavor}_instance-name")
    end

    test "rejects entity://agent/<name> (no flavor prefix)" do
      assert {:error, {:missing_flavor_prefix, _, _}} =
               AgentTypeRegistry.validate_uri("entity://agent/just-a-name")
    end

    test "rejects entity://agent/unknown-flavor_x" do
      assert {:error, {:unknown_agent_flavor, "unknown-flavor-zzzzz", _}} =
               AgentTypeRegistry.validate_uri("entity://agent/unknown-flavor-zzzzz_x")
    end

    test "rejects non-entity scheme" do
      assert {:error, {:not_agent_entity_uri, _}} =
               AgentTypeRegistry.validate_uri("entity://user/admin")
    end

    test "rejects malformed URIs" do
      assert {:error, {:bad_uri, _}} = AgentTypeRegistry.validate_uri("not a uri at all !@#")
    end
  end
end
