defmodule EsrDomainPython do
  @moduledoc """
  Python plugin host domain — placeholder.

  Phase 6 PR 11 lands the **contract** for a future Python plugin
  ecosystem; the **runtime** (port + subprocess supervisor) ships in
  Phase 7+. The placeholder is real code because the contract itself
  is load-bearing: every Phase 6 design decision that mentions "Python
  plugin" implicitly assumes this surface.

  ## Why Python plugins

  Per the SPEC north-star: ESR core is Elixir, but most agent authors
  write in Python. A Python plugin is one process per plugin, talking
  to the BEAM via line-delimited JSON-RPC over stdio. The BEAM owns
  state (registries / Repo); the Python side owns business logic
  (Behavior :invoke implementations, Template :instantiate effects).

  ## Contract — `EsrDomainPython.JsonRpc`

  See the module for the full spec. Summary:

  - Frame: `Content-Length: N\r\n\r\n<json>` (LSP framing — single
    parser, no line-mode ambiguity around embedded newlines).
  - Request: `{"jsonrpc": "2.0", "id": N, "method": "...", "params": {}}`
  - Response: `{"jsonrpc": "2.0", "id": N, "result": ...}` or
    `{"jsonrpc": "2.0", "id": N, "error": {"code": N, "message": "..."}}`
  - Notification: `{"jsonrpc": "2.0", "method": "...", "params": {}}` (no id)

  ## Methods (BEAM → Python)

  - `behavior.invoke` — `{kind, action, slice, args, ctx}` → `{ok, new_slice, output}` |
    `{error, reason}`
  - `behavior.actions` — `{}` → `[action_atoms]`
  - `behavior.state_slice` — `{}` → `slice_key_atom`
  - `behavior.init_slice` — `{args}` → `initial_slice_map`
  - `template.form_fields` — `{}` → `[%{name, label, type, required}]`
  - `template.instantiate` — `{args}` → `{ok, %{...}}` | `{error, reason}`

  ## Methods (Python → BEAM)

  - `kind.lookup` — `{uri}` → `{found, pid?, kind_module?}`
  - `dispatch` — `{target, mode, args, ctx}` → `{ok, result}` | `{error, reason}`
  - `audit.log` — `{level, event, meta}` → notification, no response

  ## Why JSON-RPC over the alternatives

  Considered: protobuf+grpc / msgpack / native Elixir-NIF.

  Picked JSON-RPC stdio because:
  - Plain JSON parses in every language (no schema compiler).
  - stdio is the simplest channel — no port allocation, no auth, the
    BEAM controls subprocess lifecycle directly.
  - LSP-style framing is already battle-tested in editor tooling.
  - Performance is fine for plugins doing ms-scale work (network LLM
    calls dominate; the JSON encode/decode overhead is in the noise).
  """
end
