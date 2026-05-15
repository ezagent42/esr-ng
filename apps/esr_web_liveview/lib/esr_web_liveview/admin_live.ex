defmodule EsrWebLiveview.AdminLive do
  @moduledoc """
  /admin LiveView — Phase 1's "Allen can drive the system" surface.

  Three interactive bits:
  1. **Echo button** — one-click dispatch of `agent://echo/behavior/echo/say`
     with a fixed `"hello"` payload. Verifies dispatch round-trip without
     the user needing to type anything.
  2. **Manual dispatch form** — target URI / args (JSON) / mode. Drives
     arbitrary invocations. Used in 1a-G4 VERIFICATION step 3.
  3. **Audit log stream** — `Phoenix.LiveView.stream` bounded to 50
     entries, subscribed to `Esr.Audit.stream_topic/0`. Each new
     `{:audit_event, _}` arrives via `handle_info` and pushes to the
     stream so the table updates in place (no full re-render).

  Per DECISIONS P1-D4: this is the §5.7.6-legitimate broadcast usage —
  audit is a view-fanout topic, audience is undefined observers, so a
  `PubSub.broadcast` is allowed (and is what `Esr.Audit` does).
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @echo_target URI.parse("agent://echo/behavior/echo/say")

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EsrCore.PubSub, Esr.Audit.stream_topic())
    end

    # Load the last 50 invocations from SQLite so audit history is
    # visible across BEAM restarts. This is the F8-subset preview
    # called out in VERIFICATION 1a-G4 step 4 — Phase 1 only restores
    # audit history, not Kind state (which Phase 3 handles).
    historical = load_recent_invocations(50)

    socket =
      socket
      |> stream(:invocations, historical, limit: 50)
      |> assign(:caller_uri_str, URI.to_string(Esr.Entity.User.admin_uri()))
      |> assign(:flash_error, nil)
      |> assign(:form,
        to_form(%{"target" => "", "args" => "", "mode" => "call"}, as: "manual_dispatch")
      )

    {:ok, socket}
  end

  defp load_recent_invocations(n) do
    %{rows: rows} =
      EsrCore.Repo.query!(
        "SELECT target, action, authz, duration_us, inserted_at " <>
          "FROM invocations ORDER BY id DESC LIMIT ?",
        [n]
      )

    Enum.map(rows, fn [target, action, authz, duration_us, inserted_at] ->
      %{
        id: "hist-#{:erlang.unique_integer([:positive, :monotonic])}",
        target: target,
        action: action || "—",
        authz: authz,
        result: "ok",
        duration_us: duration_us,
        at: format_inserted_at(inserted_at)
      }
    end)
  end

  defp format_inserted_at(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_inserted_at(s) when is_binary(s), do: s
  defp format_inserted_at(other), do: inspect(other)

  # --- Audit stream handler ---------------------------------------------

  @impl true
  def handle_info({:audit_event, event}, socket) do
    row = event_to_row(event)
    {:noreply, stream_insert(socket, :invocations, row, at: 0)}
  end

  # --- User actions -----------------------------------------------------

  @impl true
  def handle_event("echo_test", _params, socket) do
    inv = %Esr.Invocation{
      target: @echo_target,
      mode: :call,
      args: %{msg: "hello"},
      ctx: ctx()
    }

    case Esr.Invocation.dispatch(inv) do
      {:ok, _result} ->
        {:noreply, assign(socket, :flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Echo failed: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "manual_dispatch",
        %{"manual_dispatch" => %{"target" => target, "args" => args_json, "mode" => mode}},
        socket
      ) do
    with {:ok, target_uri} <- safe_uri(target),
         {:ok, args_map} <- safe_args(args_json),
         {:ok, mode_atom} <- safe_mode(mode) do
      inv = %Esr.Invocation{
        target: target_uri,
        mode: mode_atom,
        args: args_map,
        ctx: ctx()
      }

      case Esr.Invocation.dispatch(inv) do
        {:ok, _} -> {:noreply, assign(socket, :flash_error, nil)}
        :ok -> {:noreply, assign(socket, :flash_error, nil)}
        {:error, reason} -> {:noreply, assign(socket, :flash_error, "Dispatch failed: #{inspect(reason)}")}
      end
    else
      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, reason)}
    end
  end

  # --- Render -----------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 900px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">Admin</h1>
        <p style="font-size: 13px; color: #666;">
          Caller: <code>{@caller_uri_str}</code>
        </p>
      </header>

      <section id="quick-actions" style="margin-top: 24px;">
        <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">Quick Actions</h2>
        <button
          type="button"
          phx-click="echo_test"
          id="echo-test-btn"
          style="padding: 8px 16px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer;"
        >
          Echo 测试
        </button>
      </section>

      <section id="manual-dispatch" style="margin-top: 24px;">
        <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">Manual Dispatch</h2>
        <.form for={@form} phx-submit="manual_dispatch">
          <div style="margin-bottom: 8px;">
            <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_target">target</label>
            <input
              type="text"
              name="manual_dispatch[target]"
              id="manual_dispatch_target"
              placeholder="agent://echo/behavior/echo/say"
              style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
            />
          </div>
          <div style="margin-bottom: 8px;">
            <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_args">args (JSON)</label>
            <input
              type="text"
              name="manual_dispatch[args]"
              id="manual_dispatch_args"
              placeholder='{"msg": "hello"}'
              style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
            />
          </div>
          <div style="margin-bottom: 8px;">
            <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_mode">mode</label>
            <select
              name="manual_dispatch[mode]"
              id="manual_dispatch_mode"
              style="padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
            >
              <option value="call">call</option>
              <option value="cast">cast</option>
            </select>
          </div>
          <button
            type="submit"
            style="padding: 8px 16px; background: white; color: #0969da; border: 1px solid #0969da; border-radius: 4px; cursor: pointer;"
          >
            Dispatch
          </button>
        </.form>

        <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 8px;">{@flash_error}</p>
      </section>

      <section id="audit-stream" style="margin-top: 24px;">
        <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">Audit Log (last 50)</h2>
        <table style="width: 100%; font-size: 13px; border-collapse: collapse;">
          <thead>
            <tr style="border-bottom: 1px solid #d1d5da;">
              <th style="text-align: left; padding: 6px 0;">target</th>
              <th style="text-align: left;">action</th>
              <th style="text-align: left;">authz</th>
              <th style="text-align: left;">result</th>
              <th style="text-align: left;">duration_us</th>
              <th style="text-align: left;">at</th>
            </tr>
          </thead>
          <tbody id="invocations" phx-update="stream">
            <tr :for={{dom_id, row} <- @streams.invocations} id={dom_id} style="border-bottom: 1px solid #eee;">
              <td style="padding: 4px 0; font-family: monospace; font-size: 11px;">{row.target}</td>
              <td>{row.action}</td>
              <td>{row.authz}</td>
              <td style="font-family: monospace; font-size: 11px;">{row.result}</td>
              <td>{row.duration_us}</td>
              <td style="color: #666;">{row.at}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  # --- Helpers ----------------------------------------------------------

  defp ctx do
    %{
      caller: Esr.Entity.User.admin_uri(),
      caps: Esr.Entity.User.admin_caps(),
      reply: :ignore
    }
  end

  defp event_to_row(%{event: event, measurements: m, metadata: meta, at: at}) do
    %{
      id: "ev-#{:erlang.unique_integer([:positive, :monotonic])}",
      target: Map.get(meta, :target, "—"),
      action: stringify(Map.get(meta, :action)),
      authz: authz_label(event),
      result: result_label(event, meta),
      duration_us: Map.get(m, :duration_us, 0),
      at: DateTime.to_iso8601(at)
    }
  end

  defp authz_label([:esr, :invoke, :stop]), do: "stub_grant"
  defp authz_label([:esr, :invoke, :error]), do: "—"
  defp authz_label(_), do: "—"

  defp result_label([:esr, :invoke, :stop], _meta), do: "ok"
  defp result_label([:esr, :invoke, :error], %{reason: r}), do: "err: #{inspect(r)}"
  defp result_label(_, _), do: "—"

  defp stringify(nil), do: "—"
  defp stringify(a) when is_atom(a), do: Atom.to_string(a)
  defp stringify(s) when is_binary(s), do: s

  defp safe_uri(s) when is_binary(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: nil}} -> {:error, "target must include a scheme (e.g. agent://...)"}
      {:ok, uri} -> {:ok, uri}
      {:error, _} -> {:error, "malformed URI"}
    end
  end

  defp safe_uri(_), do: {:error, "target missing"}

  defp safe_args(""), do: {:ok, %{}}

  defp safe_args(json) when is_binary(json) do
    case Jason.decode(json, keys: :atoms) do
      {:ok, m} when is_map(m) -> {:ok, m}
      {:ok, _} -> {:error, "args must be a JSON object"}
      {:error, _} -> {:error, "invalid JSON in args"}
    end
  end

  defp safe_args(_), do: {:ok, %{}}

  defp safe_mode("call"), do: {:ok, :call}
  defp safe_mode("cast"), do: {:ok, :cast}
  defp safe_mode(other), do: {:error, "unsupported mode: #{inspect(other)}"}
end
