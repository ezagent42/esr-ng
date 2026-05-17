defmodule EsrPluginCcChannel.Channel do
  @moduledoc """
  Phase 6 PR 4 — Phoenix.Channel that hosts one CC bridge session.

  Topic shape: `cc:bridge:<agent_uri>` — agent_uri must match the
  Socket-level token auth (the Socket pre-filled
  `socket.assigns.agent_uri`). Join asserts the topic matches.

  ## Lifecycle
  - `join/3` — bind socket pid as the bridge for `agent_uri` via
    `Esr.Bridge.V2.Registry.bind/2` (a new tiny registry — see
    EsrPluginCcChannel.BridgeRegistry).
  - `handle_in("reply", %{...})` — bridge POSTs an outbound reply
    (claude's tool call result). Dispatches `chat/send` on each
    target session.
  - `terminate/2` — unbind on socket close.

  ## Why a separate Channel module (not put logic in Socket)

  Socket = auth + per-connection assigns. Channel = topic-scoped
  message routing. The split lets multiple bridges share the same
  Socket process while each owns its own Channel pid.

  ## Push direction (BEAM → bridge)

  External callers (chat plugin's Agent receive handler) reach the
  bridge by sending `{:to_claude, payload}` to the bound Channel pid.
  The Channel forwards via `push(socket, "to_claude", payload)` so
  the WS client gets a real Phoenix.Channel event.
  """
  use Phoenix.Channel

  alias EsrPluginCcChannel.BridgeRegistry

  @impl true
  def join("cc:bridge:" <> _topic_uri, _params, socket) do
    case BridgeRegistry.bind(socket.assigns.agent_uri, self()) do
      :ok -> {:ok, socket}
      {:error, reason} -> {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def handle_in("reply", %{"text" => text, "session_uris" => sessions} = params, socket)
      when is_binary(text) and is_list(sessions) do
    ref = Map.get(params, "ref")
    GenServer.cast(socket.transport_pid, :ok)

    send(self(), {:dispatch_reply, sessions, text, ref})
    {:noreply, socket}
  end

  def handle_in("reply", _other, socket) do
    {:reply, {:error, %{reason: "reply requires text + session_uris"}}, socket}
  end

  def handle_in(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:to_claude, payload}, socket) do
    push(socket, "to_claude", payload)
    {:noreply, socket}
  end

  def handle_info({:dispatch_reply, sessions, text, ref}, socket) do
    agent_uri = socket.assigns.agent_uri

    ref_uri =
      case ref do
        nil -> nil
        "" -> nil
        s when is_binary(s) -> URI.new!(s)
      end

    msg = Esr.Message.new(agent_uri, %{text: text, attachments: []}, ref: ref_uri)

    for session_uri_str <- sessions do
      target = URI.new!("#{session_uri_str}/behavior/chat/send")

      Esr.Invocation.dispatch(%Esr.Invocation{
        target: target,
        mode: :cast,
        args: %{message: msg},
        ctx: %{
          caller: agent_uri,
          caps: Esr.Entity.User.admin_caps(),
          reply: :ignore
        }
      })
    end

    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    BridgeRegistry.unbind(socket.assigns.agent_uri)
    :ok
  end
end
