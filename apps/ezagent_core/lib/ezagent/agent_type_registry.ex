defmodule Ezagent.AgentTypeRegistry do
  @moduledoc """
  Registry for agent flavor → spawn fn dispatch.

  ## SPEC v2 (PR #141 onwards)

  Agent URIs are now `entity://agent/<flavor>_<name>` (SPEC §5.14).
  The flavor (cc / curl / echo / ...) is a free-form prefix on the
  name segment, separated from the rest of the name by an underscore.

      entity://agent/cc_demo-builder     # flavor=cc, name=demo-builder
      entity://agent/curl_my-deepseek    # flavor=curl, name=my-deepseek
      entity://agent/echo_default        # flavor=echo, name=default
      entity://agent/test_X              # flavor=test (test fixtures)

  Each plugin that provides an agent flavor registers a flavor name +
  spawn function at boot:

      Ezagent.AgentTypeRegistry.register("curl", fn uri, name ->
        DynamicSupervisor.start_child(
          EzagentPluginCurlAgent.InstanceSupervisor,
          {Ezagent.Kind.Server, {Ezagent.Entity.CurlAgent, %{uri: uri}}}
        )
      end)

  The chat plugin's `entity://` `Ezagent.SpawnRegistry` fn dispatches
  on `uri.host`: for `host = "agent"`, it delegates to
  `AgentTypeRegistry.spawn/1` which extracts the flavor and looks
  up the registered fn.

  ## Why this still exists

  SPEC §5.14 says "the AgentTemplate that instantiated the agent" is
  the authoritative source for "which Behavior runs this agent". PR
  #147 will retire this registry in favor of Template-owned kind_module
  wiring. PR #141 keeps it for the mechanical scheme migration; the
  spawn semantics (one fn per flavor) are unchanged.

  ## Naming convention

  `register/2` takes a flavor string (`"cc"`, `"curl"`, `"echo"`,
  `"test"`). The flavor MUST match the name-prefix the operator uses
  when constructing URIs. The spawn fn receives the full URI and the
  full name string (e.g. `"cc_demo-builder"`) — NOT the
  flavor-stripped tail. This keeps the spawn fn URI-faithful;
  callers that want the stripped tail can split themselves.
  """

  @table :ezagent_agent_type_registry

  @doc "ETS table name — EtsOwner consults this at boot."
  def table, do: @table

  @doc """
  Standalone init (tests). Production path is EtsOwner.init/1 which
  creates the table per @tables in EzagentCore.EtsOwner.
  """
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @type flavor_name :: String.t()
  @type spawn_fn :: (URI.t(), String.t() -> {:ok, pid()} | {:error, term()})

  @doc """
  Register `flavor` → `spawn_fn`. Plugins call this in their
  `Application.start/2`. Re-registration overwrites silently
  (matches `SpawnRegistry.register/2` semantics — late-binding
  plugins win).
  """
  @spec register(flavor_name(), spawn_fn()) :: :ok
  def register(flavor, fun) when is_binary(flavor) and is_function(fun, 2) do
    :ets.insert(@table, {flavor, fun})
    :ok
  end

  @doc """
  List currently registered flavor names (for debugging + the LV's
  template Class picker which can render them as a dropdown).
  """
  @spec registered_flavors() :: [flavor_name()]
  def registered_flavors do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {flavor, _} -> flavor end)
    |> Enum.sort()
  end

  # Kept as an alias for migration ergonomics — `registered_types/0`
  # was the pre-PR-141 name. New code should prefer `registered_flavors/0`.
  @doc false
  def registered_types, do: registered_flavors()

  @doc """
  Spawn (or look up an existing) Kind at the given URI.

  - `entity://agent/<flavor>_<name>` → split on first `_`, dispatch
    by `flavor` to the registered spawn fn (full name passed through)
  - `entity://agent/<name-without-underscore>` →
    `{:error, :missing_flavor_prefix}`
  - Other URIs → `{:error, :not_agent_entity_uri}`

  Returns `{:ok, pid}` either way for valid known flavors; concrete
  error for invalid shapes.
  """
  @spec spawn(URI.t()) :: {:ok, pid()} | {:error, term()}
  def spawn(%URI{scheme: "entity", host: "agent", path: "/" <> name})
      when is_binary(name) and name != "" do
    case String.split(name, "_", parts: 2) do
      [flavor, _rest] when flavor != "" ->
        dispatch_flavor(flavor, name)

      _ ->
        {:error, {:missing_flavor_prefix, name}}
    end
  end

  def spawn(%URI{scheme: "entity", host: "agent", path: nil}) do
    {:error, {:missing_name, "entity://agent/"}}
  end

  def spawn(%URI{} = uri) do
    {:error, {:not_agent_entity_uri, URI.to_string(uri)}}
  end

  defp dispatch_flavor(flavor, name) do
    case :ets.lookup(@table, flavor) do
      [{^flavor, fun}] ->
        full_uri = URI.new!("entity://agent/#{name}")

        case fun.(full_uri, name) do
          {:ok, _pid} = ok -> ok
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end

      [] ->
        {:error, {:unknown_agent_flavor, flavor}}
    end
  end

  @doc """
  Strict validator for the `entity://agent/<flavor>_<name>` shape.
  Returns `:ok` or `{:error, reason}`. Used by Template Class
  validators to reject legacy URIs at template-add time.
  """
  @spec validate_uri(String.t() | URI.t()) :: :ok | {:error, term()}
  def validate_uri(%URI{} = uri), do: do_validate(uri)

  def validate_uri(uri_str) when is_binary(uri_str) do
    case URI.new(uri_str) do
      {:ok, %URI{} = uri} -> do_validate(uri)
      _ -> {:error, {:bad_uri, uri_str}}
    end
  end

  defp do_validate(%URI{scheme: "entity", host: "agent", path: "/" <> name})
       when is_binary(name) and name != "" do
    case String.split(name, "_", parts: 2) do
      [flavor, rest] when flavor != "" and rest != "" ->
        if known_flavor?(flavor) do
          :ok
        else
          {:error, {:unknown_agent_flavor, flavor, registered_flavors()}}
        end

      _ ->
        {:error,
         {:missing_flavor_prefix, name,
          "agent URIs must be `entity://agent/<flavor>_<name>` " <>
            "(SPEC v2 §5.14 / PR #141)"}}
    end
  end

  defp do_validate(%URI{scheme: "entity", host: "agent"} = uri) do
    {:error, {:invalid_agent_uri_shape, URI.to_string(uri)}}
  end

  defp do_validate(%URI{} = uri) do
    {:error, {:not_agent_entity_uri, URI.to_string(uri)}}
  end

  defp known_flavor?(flavor) when is_binary(flavor) do
    case :ets.lookup(@table, flavor) do
      [_] -> true
      [] -> false
    end
  end
end
