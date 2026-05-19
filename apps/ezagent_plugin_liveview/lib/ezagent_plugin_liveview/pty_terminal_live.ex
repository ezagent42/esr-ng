defmodule EzagentPluginLiveview.PtyTerminalLive do
  @moduledoc """
  Phase 5 PR 4: Pty-Web — xterm.js rendering of a live cc-pty TUI in
  the browser.

  ## Architecture (per IMPLEMENTATION_ROADMAP §1.3 #1)

  - Output: PtyServer broadcasts each stdout/stderr chunk to
    `pty:output:<agent_uri>` PubSub. LV subscribes and pushes the
    raw bytes to xterm via `push_event(socket, "pty_chunk", %{bytes})`
  - Input: xterm hook `onData` fires `pushEvent("pty_input", {bytes})`
    → this LV's `handle_event("pty_input", ...)` → `Ezagent.Invocation.dispatch`
    to `pty-input://default/behavior/pty/write` (CapBAC + audit fire)
    → `Ezagent.Behavior.Pty.invoke(:write, ...)` looks up PtyServer and
    writes the bytes

  **Never pushes input directly to PubSub.** The dispatch path is the
  enforced invariant (`agents_pty_input_dispatch_test.exs`).

  ## URL

  `/admin/agents/:uri/terminal` — `:uri` is URI-encoded `entity://agent/...`
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @impl true
  def mount(%{"uri" => encoded_uri}, session, socket) do
    case parse_agent_uri(encoded_uri) do
      {:ok, agent_uri} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            EzagentCore.PubSub,
            Ezagent.PluginCc.PtyServer.output_topic(agent_uri)
          )

          # PR #128 — ttyd-style initial render. Two complementary
          # nudges so the operator never sees a black terminal:
          # (1) replay the PtyServer's recent buffer so the LAST
          # ANSI-rendered screen the TUI emitted shows immediately
          # (sufficient for most cases — claude's full screen is
          # almost always within the last 64KB of output);
          # (2) trigger a winsize nudge so the TUI redraws fresh
          # output through the live PubSub path, covering the case
          # where the last redraw is older than the buffer window.
          send(self(), {:initial_render, agent_uri})
        end

        {:ok,
         socket
         |> assign(:not_found, false)
         |> assign(:agent_uri, agent_uri)
         |> assign(:flash_error, nil)
         |> assign(:dispatch_target, dispatch_target_uri())
         |> assign_caller(session)}

      _ ->
        {:ok, assign(socket, :not_found, true) |> assign(:bad_uri, encoded_uri)}
    end
  end

  defp assign_caller(socket, _session) do
    # PR #123 hardening: on_mount hook set current_entity_uri; admin
    # fallback deleted (was a public-WS-reconnect privilege-escalation
    # path pre-hardening).
    caller_uri = socket.assigns.current_entity_uri

    caller_caps =
      if URI.to_string(caller_uri) == URI.to_string(Ezagent.Entity.User.admin_uri()) do
        Ezagent.Entity.User.admin_caps()
      else
        Ezagent.Identity.list_caps_for(caller_uri)
      end

    socket
    |> assign(:caller_uri, caller_uri)
    |> assign(:caller_caps, caller_caps)
  end

  defp dispatch_target_uri,
    do:
      URI.parse(
        URI.to_string(Ezagent.Entity.PtyInput.default_uri()) <>
          "/behavior/pty/write"
      )

  defp parse_agent_uri(encoded) do
    decoded = URI.decode_www_form(encoded)

    case URI.new(decoded) do
      {:ok, %URI{scheme: "agent"} = uri} -> {:ok, uri}
      _ -> :error
    end
  end

  @impl true
  def handle_info({:pty_output, _agent_uri, chunk}, socket) do
    {:noreply, push_event(socket, "pty_chunk", %{bytes: chunk})}
  end

  # PR #128 — push the PtyServer's accumulated stdout buffer to
  # xterm immediately on mount, then trigger a winsize nudge to
  # provoke a fresh TUI redraw. Both fail silently if the agent
  # isn't a live PtyServer (e.g. v2-only Channel-bridged agents
  # with no local PTY).
  def handle_info({:initial_render, agent_uri}, socket) do
    case Ezagent.PluginCc.PtyServer.snapshot_buffer(agent_uri) do
      {:ok, buf} when byte_size(buf) > 0 ->
        socket = push_event(socket, "pty_chunk", %{bytes: buf})
        _ = Ezagent.PluginCc.PtyServer.trigger_redraw(agent_uri)
        {:noreply, socket}

      _ ->
        _ = Ezagent.PluginCc.PtyServer.trigger_redraw(agent_uri)
        {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("pty_input", %{"bytes" => bytes}, socket) when is_binary(bytes) do
    inv = %Ezagent.Invocation{
      target: socket.assigns.dispatch_target,
      mode: :cast,
      args: %{agent_uri: URI.to_string(socket.assigns.agent_uri), bytes: bytes},
      ctx: %{
        caller: socket.assigns.caller_uri,
        caps: socket.assigns.caller_caps,
        reply: :ignore
      }
    }

    case Ezagent.Invocation.dispatch(inv) do
      {:ok, _} ->
        {:noreply, socket}

      :ok ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :flash_error,
           "Unauthorized — need pty_input cap. Ask admin to grant it."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Input failed: #{inspect(reason)}")}
    end
  end

  def handle_event("pty_resize", %{"cols" => _cols, "rows" => _rows}, socket) do
    # v1: best-effort log only. Phase 5 PR 4 follow-up could dispatch a
    # pty/resize action; not blocking the demo.
    {:noreply, socket}
  end

  @impl true
  def render(%{not_found: true} = assigns) do
    ~H"""
    <div style="max-width: 800px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <h1>Agent URI invalid</h1>
      <p><code>{@bad_uri}</code></p>
      <p><a href="/admin/agents" style="color: #0969da;">← Agents</a></p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="max-width: 1200px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">
          Pty-Web: <code>{URI.to_string(@agent_uri)}</code>
        </h1>
        <p style="font-size: 13px; color: #666;">
          <a href={"/admin/agents/#{URI.encode_www_form(URI.to_string(@agent_uri))}"} style="color: #0969da;">← Agent status</a>
          <span style="margin-left: 16px;">
            Input → <code>Ezagent.Invocation.dispatch</code> → CapBAC → audit → PTY.
          </span>
        </p>
      </header>

      <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 12px;">
        {@flash_error}
      </p>

      <div
        id={"pty-terminal-" <> Base.url_encode64(URI.to_string(@agent_uri), padding: false)}
        phx-hook="PtyTerminal"
        phx-update="ignore"
        style="margin-top: 16px; height: 540px; background: #1e1e1e; border: 1px solid #333; border-radius: 4px; padding: 8px;"
      ></div>

      <p style="font-size: 11px; color: #57606a; margin-top: 8px;">
        Type to send input. Output streams via <code>pty:output:&lt;agent_uri&gt;</code> PubSub.
      </p>
    </div>
    """
  end
end
