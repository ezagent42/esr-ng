defmodule Esr.Bridge.V1Prototype.Server do
  @moduledoc """
  Phase 1 prototype CC stdio bridge — wraps a spawned Python subprocess
  whose stdio speaks line-delimited JSON-RPC.

  ## What this proves

  The architecture's bridge model (bridge↔ESR via stdio JSON-RPC, per
  P1-D1) end-to-end:

  - `start_link/1` spawns `python3 esr_bridge_v1_prototype.py` via
    `Port.open/2` with `:binary, :line` so stdout lines arrive as
    discrete messages
  - inbound JSON-RPC requests go out via `Port.command/2`
  - outbound replies are decoded in `handle_info/2` and either:
    - matched against a `from` reference in `state.pending` (for
      `call/2`-style requests), reply to the awaiting caller, or
    - emitted as a `{:bridge_event, msg}` PubSub broadcast on the
      bridge's events topic (for unsolicited messages like the
      initial `hello`)

  ## v1_prototype scope

  - One bridge process; Phase 5's plugin handles supervisor/dynamic
    spawning + multiple CC instances + lifecycle
  - No actual Claude Code on the other side — the bridge is the
    echo Python script. Phase 5 replaces both halves.
  - Uses stdlib `Port` not `:erlexec` to keep deps minimal — the
    `OSProcess` Behavior arrives in Phase 5 and will replace this
    spawn line. **TODO Phase 5: replace Port.open with OSProcess.start**

  ## Process lifecycle telemetry

  `[:esr, :bridge_v1, :spawned]` on init success
  `[:esr, :bridge_v1, :exited]` on EXIT / process death

  These let LiveView /admin show a "bridge alive" badge by counting
  spawned − exited.
  """

  use GenServer
  require Logger

  defstruct [
    :port,
    :script_path,
    :hello_received,
    pending: %{},
    next_id: 1
  ]

  @bridge_topic "esr:bridge_v1:events"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Topic for LV / other subscribers to subscribe to bridge events."
  def topic, do: @bridge_topic

  @doc """
  Send a JSON-RPC request to the bridge and wait for its reply.

  Returns `{:ok, result}` or `{:error, reason}`. Times out after
  `timeout_ms` (default 5_000).
  """
  @spec call(method :: String.t(), params :: map(), timeout_ms :: pos_integer()) ::
          {:ok, term()} | {:error, term()}
  def call(method, params \\ %{}, timeout_ms \\ 5_000) do
    GenServer.call(__MODULE__, {:rpc, method, params}, timeout_ms + 1_000)
  end

  @doc "Is the bridge process alive + initialized?"
  def status do
    case Process.whereis(__MODULE__) do
      nil -> :down
      pid -> GenServer.call(pid, :status)
    end
  end

  # --- callbacks --------------------------------------------------------

  @impl true
  def init(opts) do
    script_path =
      opts[:script_path] ||
        Path.join([
          Application.app_dir(:esr_plugin_cc_bridge_v1_prototype),
          "..",
          "..",
          "..",
          "..",
          "apps",
          "esr_plugin_cc_bridge_v1_prototype",
          "python",
          "esr_bridge_v1_prototype.py"
        ])
        |> Path.expand()

    python_bin = System.find_executable("python3") || "/usr/bin/env python3"

    port =
      Port.open(
        {:spawn_executable, python_bin},
        [
          :binary,
          {:line, 8 * 1024},
          :exit_status,
          {:args, [script_path]}
        ]
      )

    :telemetry.execute([:esr, :bridge_v1, :spawned], %{}, %{port: port, script: script_path})

    {:ok,
     %__MODULE__{
       port: port,
       script_path: script_path,
       hello_received: false
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status =
      cond do
        is_nil(state.port) -> :down
        state.hello_received -> :ready
        true -> :starting
      end

    {:reply, status, state}
  end

  def handle_call({:rpc, method, params}, from, state) do
    id = "req-#{state.next_id}"

    payload =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => params
      })

    Port.command(state.port, payload <> "\n")

    new_state = %{
      state
      | pending: Map.put(state.pending, id, from),
        next_id: state.next_id + 1
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, %{"method" => "hello"} = msg} ->
        Phoenix.PubSub.broadcast(EsrCore.PubSub, @bridge_topic, {:bridge_event, msg})
        {:noreply, %{state | hello_received: true}}

      {:ok, %{"id" => id, "result" => result}} ->
        new_pending = reply_to_pending(state.pending, id, {:ok, result})
        Phoenix.PubSub.broadcast(EsrCore.PubSub, @bridge_topic, {:bridge_reply, id, result})
        {:noreply, %{state | pending: new_pending}}

      {:ok, %{"id" => id, "error" => err}} ->
        new_pending = reply_to_pending(state.pending, id, {:error, err})
        {:noreply, %{state | pending: new_pending}}

      {:ok, msg} ->
        Phoenix.PubSub.broadcast(EsrCore.PubSub, @bridge_topic, {:bridge_event, msg})
        {:noreply, state}

      {:error, _} ->
        Logger.warning("Bridge V1 received non-JSON line: #{inspect(line)}")
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    :telemetry.execute([:esr, :bridge_v1, :exited], %{}, %{exit_status: status})
    Logger.info("Bridge V1 exited with status=#{status}")

    Phoenix.PubSub.broadcast(EsrCore.PubSub, @bridge_topic, {:bridge_exited, status})

    # Fail any pending RPC calls.
    Enum.each(state.pending, fn {_id, from} ->
      GenServer.reply(from, {:error, {:bridge_exited, status}})
    end)

    {:stop, :normal, %{state | port: nil, pending: %{}}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp reply_to_pending(pending, id, reply) do
    case Map.pop(pending, id) do
      {nil, p} -> p
      {from, p} -> GenServer.reply(from, reply) && p
    end
  end
end
