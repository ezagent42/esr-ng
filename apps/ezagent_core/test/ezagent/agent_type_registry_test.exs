defmodule Ezagent.AgentTypeRegistryTest do
  use ExUnit.Case, async: false

  alias Ezagent.AgentTypeRegistry

  setup do
    AgentTypeRegistry.init()

    # Clean slate for each test — wipe any registrations our test made
    # (other plugins' real registrations stay; tests use unique type names).
    :ok
  end

  describe "register/2 + registered_types/0" do
    test "registers a type and exposes it via registered_types" do
      type = "test-type-#{System.unique_integer([:positive])}"

      :ok =
        AgentTypeRegistry.register(type, fn _uri, name ->
          send(self(), {:spawned, name})
          {:ok, self()}
        end)

      assert type in AgentTypeRegistry.registered_types()
    end
  end

  describe "spawn/1 — dispatch by URI type segment" do
    test "calls the registered fn with the URI + name" do
      type = "deldist-#{System.unique_integer([:positive])}"
      this = self()

      :ok =
        AgentTypeRegistry.register(type, fn uri, name ->
          send(this, {:dispatched, uri, name})
          {:ok, this}
        end)

      uri = URI.new!("agent://#{type}/the-name")
      assert {:ok, ^this} = AgentTypeRegistry.spawn(uri)
      assert_receive {:dispatched, ^uri, "the-name"}, 200
    end

    test "rejects URI without type segment" do
      assert {:error, {:missing_type_segment, "no-type"}} =
               AgentTypeRegistry.spawn(URI.new!("agent://no-type"))
    end

    test "rejects unknown type" do
      assert {:error, {:unknown_agent_type, "made-up-type-xyz"}} =
               AgentTypeRegistry.spawn(URI.new!("agent://made-up-type-xyz/x"))
    end

    test "rejects non-agent scheme" do
      assert {:error, {:not_agent_scheme, "session"}} =
               AgentTypeRegistry.spawn(URI.new!("session://main"))
    end

    test "passes through {:already_started, pid} as success" do
      type = "alread-#{System.unique_integer([:positive])}"
      target_pid = spawn(fn -> Process.sleep(:infinity) end)

      :ok =
        AgentTypeRegistry.register(type, fn _uri, _name ->
          {:error, {:already_started, target_pid}}
        end)

      assert {:ok, ^target_pid} =
               AgentTypeRegistry.spawn(URI.new!("agent://#{type}/x"))
    end
  end

  describe "validate_uri/1 — strict shape check" do
    setup do
      type = "validatest-#{System.unique_integer([:positive])}"
      :ok = AgentTypeRegistry.register(type, fn _uri, _name -> {:ok, self()} end)
      {:ok, type: type}
    end

    test "accepts agent://<type>/<name> for a registered type", %{type: type} do
      assert :ok = AgentTypeRegistry.validate_uri("agent://#{type}/instance-name")
    end

    test "rejects agent://<name> (no type segment)" do
      assert {:error, {:missing_type_segment, _, _}} =
               AgentTypeRegistry.validate_uri("agent://just-a-name")
    end

    test "rejects agent://unknown-type/x" do
      assert {:error, {:unknown_agent_type, "unknown-type-zzzzz", _}} =
               AgentTypeRegistry.validate_uri("agent://unknown-type-zzzzz/x")
    end

    test "rejects non-agent scheme" do
      assert {:error, {:not_agent_scheme, "user"}} =
               AgentTypeRegistry.validate_uri("user://admin")
    end

    test "rejects malformed URIs" do
      assert {:error, {:bad_uri, _}} = AgentTypeRegistry.validate_uri("not a uri at all !@#")
    end
  end
end
