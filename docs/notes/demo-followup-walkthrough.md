# Demo follow-up walkthrough — agent config UI + PTY + routing + multi-agent

> Captured 2026-05-18 evening per Allen's ask:
> "录制一个 demo 视频, 我想看看如何配置新的 agent (包括配置界面、配置后打开 Pty 直接交互)、配置 session 规则、展现根据新设定的规则开始多人多 agent 的交互."

## Evidence

- `evidence/pr-demo-followup-walkthrough.webm` — agent-browser recording (1.9 MB) of the full UI walkthrough
- `evidence/demo-followup-02-template-registered.png` — workspace detail showing the new `cc.pty` template registered (Session templates 1)
- `evidence/demo-followup-03-pty-agent-live.png` — `/admin/agents` showing `agent://demo-builder` running with os_pid + `📺 terminal` link
- `evidence/demo-followup-04-claude-pty-reply.png` — xterm.js with Claude Code v2.1.143 alive in the browser; user typed "say hi in 5 words" and claude replied "Hi there, happy to help!" (Baked for 4s)
- `evidence/demo-followup-05-routing-rule.png` — `/admin/routing` showing two rules: system_default `{:always}` + new admin-added `{:mention, "agent://demo-builder"} → agent://demo-builder`
- `evidence/demo-followup-06-multi-agent-chat.png` — `/admin` chat with two messages: admin's prose + an `@echo` mention; Members panel shows both `agent://echo` + `user://admin` online; chat-compose @-mention dropdown picked up the newly-joined agent

## The 11 captured steps

1. `/admin` landing (admin already logged in via auth-hardened login)
2. Click `Workspaces →` → `/admin/workspaces`
3. Create new workspace **`demo-followup`** via the form; row appears with 0 members / 0 templates / 0 rules / **live** status
4. Click into `workspace://demo-followup` (`/admin/workspaces/demo-followup`)
5. Click the **`cc.pty`** Template Class button — the form re-renders with cc.pty-specific fields (Agent URI + Working directory)
6. Fill `template name = demo-builder-pty`, `agent_uri = agent://demo-builder`, `cwd = /tmp/demo-builder` → Add template; row appears under Session templates as **Class registered**
7. PtyServer spawns claude in `/tmp/demo-builder`; visible at `/admin/agents` as `agent://demo-builder | os_pid 32385 | running | detail → | 📺 terminal`
8. Click **📺 terminal** → `/admin/agents/agent%3A%2F%2Fdemo-builder/terminal` opens xterm.js with the moduledoc strapline "Input → Ezagent.Invocation.dispatch → CapBAC → audit → PTY"; Ctrl-L redraws → "Claude Code v2.1.143 — Welcome back Allen!" appears
9. Type "say hi in 5 words" + Enter → claude replies "Hi there, happy to help!" (PTY round-trip verified in browser)
10. Navigate `/admin/routing` → add rule: matcher type **mention**, arg `agent://demo-builder`, receivers `agent://demo-builder` → rule 2 appears as `admin | {:mention, "agent://demo-builder"} | agent://demo-builder`
11. Back to `/admin`; add `agent://echo` to session via the Floating agents `Add to session…` dropdown; Members panel shows `agent://echo online` + `user://admin online`; type a mention message with `@echo` → message routes (server log confirms `mentions: [agent://echo]` parsed + dispatch to `agent://echo/behavior/chat/receive`)

## What's proven by the recording

- **Self-describing config UI**: `Ezagent.UI.Form.form_fields/0` on the cc.pty Template Class drives the form fields automatically; no per-class UI code in the LV. Adding a new Template Class (e.g. a hypothetical `cc.cloud_agent`) automatically gets its own form without LV changes (Decision #136 + Phase 6 PR 3 shadcn-like primitives).
- **Workspace → PtyServer → claude** end-to-end: the Template Class instantiate path (`Ezagent.PluginCcPty.Template.instantiate/3`) spawns a PtyServer that runs `claude --permission-mode bypassPermissions --dangerously-load-development-channels server:esr-bridge --settings ... --mcp-config ...` under erlexec. Claude lives in `/tmp/demo-builder` with isolated `claude_config_dir`.
- **xterm.js → live PTY**: the Pty-Web LV (`/admin/agents/:uri/terminal`, Phase 5 PR 4) renders the live PTY stream in the browser via Phoenix.Channel + xterm.js. Operator keystrokes round-trip through `Ezagent.Invocation.dispatch` (CapBAC-gated) → `:exec.send/2` → claude stdin. Claude's stdout streams back via the per-agent `pty:output:<agent_uri>` PubSub topic.
- **Routing rules editable from UI**: the Form-mode editor accepts matcher type (mention | always | ...), matcher arg, receiver URIs. Adds rows to `Ezagent.Routing.RuleStore`; the live RoutingRegistry picks them up immediately (no phx restart). JSON mode for arbitrary combinators is the escape hatch.
- **Multi-agent routing**: the `@echo` mention parsed correctly into `mentions: [%URI{scheme: "agent", host: "echo"}]`. The dispatch tried `agent://echo/behavior/chat/receive` — the echo plugin doesn't implement `:receive` on Chat behavior (it implements `:say` on its own Echo behavior), so dispatch surfaced `{:unknown_action, :receive}`. That's a plugin-side gap; the routing layer worked correctly.

## What the recording does NOT show

- **demo-builder receiving via mention**: my added rule routes mentions to `agent://demo-builder`, but the cc.pty bridge stack didn't have a TokenStore mint for `agent://demo-builder` (`mix ezagent.cc_channel.register` would do that), so the Channel.join doesn't bind a Channel pid for it — `BridgeRegistry.lookup(agent://demo-builder)` returns `:error` and the inbound message is a silent no-op (as designed post-PR #118). To complete the loop:
  1. Register a CC channel instance for `agent://demo-builder` (via `cc.channel_instance` Template Class — separate row in the same workspace)
  2. The PtyServer's mcp.json will then carry an `EZAGENT_AGENT_TOKEN`, the Python WS bridge connects to `/cc_socket`, `BridgeRegistry.bind` fires, and the inbound flow lights up
- **Cloudflare tunnel**: deferred per Allen 2026-05-18 13:24 ("先不管 tunnel 的事情"). All shown traffic is on `100.64.0.27:10042` (Tailscale).

## Trade-off notes for the dev team

- The cc.pty / cc.channel_instance split is intentional (Decision #136 separation of "the OS process" from "the bridge instance"). A future quality-of-life PR could auto-instantiate the matching `cc.channel_instance` whenever a `cc.pty` template is added — saves operators a second form. Out of scope for this demo PR.
- The xterm-helper-textarea input handling works for keystrokes but doesn't natively render a blinking cursor in the agent-browser screenshot — fine for the recording, less useful for static screenshots. The video shows it live.
