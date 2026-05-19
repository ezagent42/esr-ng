defmodule Ezagent.AgentTypeRegistry do
  @moduledoc """
  PR #131 — registry for `agent://<type>/<name>` URI dispatch.

  ## Why

  Before this PR, every `agent://X` URI was a freeform name; nothing
  in the URI told you whether the agent was a Claude Code TUI, a
  curl-driven HTTP-completion proxy, an echo fixture, or something
  else. Allen 2026-05-19 03:21 directive: encode the agent type
  in the URI host segment so a glance at `agent://curl/my-deepseek`
  tells you what kind of agent you're talking to.

  ## How

  Each plugin that provides an agent flavour registers a type name
  + spawn function at boot:

      Ezagent.AgentTypeRegistry.register("curl", fn uri, name ->
        DynamicSupervisor.start_child(
          EzagentPluginCurlAgent.InstanceSupervisor,
          {Ezagent.Kind.Server, {Ezagent.Entity.CurlAgent, %{uri: uri}}}
        )
      end)

  The chat plugin's `agent://` `Ezagent.SpawnRegistry` fn delegates
  here, parsing `<type>/<name>` from the URI and looking up the
  registered fn.

  ## URI shape (strict, per Allen 2026-05-19 03:46 #3 + #4)

  - `agent://<type>/<name>` only. `<type>` must be one of the
    registered types; `<name>` is plugin-defined (typically a stable
    identifier).
  - Old `agent://<name>` (no type segment) URIs error at validate
    time — operators must rebuild with the new shape. DB migration
    rewrites the existing demo data.
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

  @type type_name :: String.t()
  @type spawn_fn :: (URI.t(), String.t() -> {:ok, pid()} | {:error, term()})

  @doc """
  Register `type` → `spawn_fn`. Plugins call this in their
  `Application.start/2`. Re-registration overwrites silently
  (matches `SpawnRegistry.register/2` semantics — late-binding
  plugins win).
  """
  @spec register(type_name(), spawn_fn()) :: :ok
  def register(type, fun) when is_binary(type) and is_function(fun, 2) do
    :ets.insert(@table, {type, fun})
    :ok
  end

  @doc """
  List currently registered type names (for debugging + the LV's
  template Class picker which can render them as a dropdown).
  """
  @spec registered_types() :: [type_name()]
  def registered_types do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {type, _} -> type end)
    |> Enum.sort()
  end

  @doc """
  Spawn (or look up an existing) Kind at the given URI.

  - `agent://<type>/<name>` → dispatch by `type` to the registered
    spawn fn
  - `agent://<name>` (no path) → `{:error, :missing_type_segment}`
  - Other schemes → `{:error, :not_agent_scheme}`

  Returns `{:ok, pid}` either way for valid known types; concrete
  error for invalid shapes.
  """
  @spec spawn(URI.t()) :: {:ok, pid()} | {:error, term()}
  def spawn(%URI{scheme: "agent", host: type, path: "/" <> name})
      when is_binary(type) and type != "" and name != "" do
    case :ets.lookup(@table, type) do
      [{^type, fun}] ->
        full_uri = URI.new!("agent://#{type}/#{name}")

        case fun.(full_uri, name) do
          {:ok, _pid} = ok -> ok
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end

      [] ->
        {:error, {:unknown_agent_type, type}}
    end
  end

  def spawn(%URI{scheme: "agent", host: host, path: nil}) when is_binary(host) do
    {:error, {:missing_type_segment, host}}
  end

  def spawn(%URI{scheme: "agent"} = uri) do
    {:error, {:invalid_agent_uri_shape, URI.to_string(uri)}}
  end

  def spawn(%URI{scheme: other}) do
    {:error, {:not_agent_scheme, other}}
  end

  @doc """
  Strict validator for the `agent://<type>/<name>` shape. Returns
  `:ok` or `{:error, reason}`. Used by Template Class validators
  to reject legacy URIs at template-add time.
  """
  @spec validate_uri(String.t() | URI.t()) :: :ok | {:error, term()}
  def validate_uri(%URI{} = uri), do: do_validate(uri)

  def validate_uri(uri_str) when is_binary(uri_str) do
    case URI.new(uri_str) do
      {:ok, %URI{} = uri} -> do_validate(uri)
      _ -> {:error, {:bad_uri, uri_str}}
    end
  end

  defp do_validate(%URI{scheme: "agent", host: type, path: "/" <> name})
       when is_binary(type) and type != "" and name != "" do
    if known_type?(type) do
      :ok
    else
      {:error, {:unknown_agent_type, type, registered_types()}}
    end
  end

  defp do_validate(%URI{scheme: "agent", host: host, path: nil}) when is_binary(host) do
    {:error,
     {:missing_type_segment, host,
      "agent URIs must be `agent://<type>/<name>` (PR #131 / Allen 2026-05-19 #4)"}}
  end

  defp do_validate(%URI{scheme: "agent"} = uri) do
    {:error, {:invalid_agent_uri_shape, URI.to_string(uri)}}
  end

  defp do_validate(%URI{scheme: other}) do
    {:error, {:not_agent_scheme, other}}
  end

  defp known_type?(type) when is_binary(type) do
    case :ets.lookup(@table, type) do
      [_] -> true
      [] -> false
    end
  end
end
