#!/usr/bin/env node
//
// Phase 6 PR 15 — Feishu WS long-connect sidecar for esr-ng.
//
// Why a Node sidecar instead of native Elixir WS:
//   The lark long-connect protocol (handshake / heartbeat / event
//   framing / dedup) is encapsulated in `@larksuiteoapi/node-sdk` and
//   not publicly documented. Re-implementing in Elixir is 300-600 LOC
//   of reverse-engineering risk. The sidecar is ~80 LOC of glue.
//
// Wire format with ESR:
//   stdin   = (unused for now; future ESR→sidecar commands)
//   stdout  = one JSON line per event:
//     {"type":"event","schema":"2.0","header":{...},"event":{...}}
//     {"type":"connected"}
//     {"type":"disconnected","reason":"..."}
//     {"type":"error","message":"..."}
//
// Credentials come via env vars (ESR sets them when spawning):
//   FEISHU_APP_ID
//   FEISHU_APP_SECRET
//   FEISHU_DOMAIN    (default "https://open.feishu.cn", set
//                     "https://open.larksuite.com" for lark.com tenants)

const lark = require('@larksuiteoapi/node-sdk');

const APP_ID = process.env.FEISHU_APP_ID;
const APP_SECRET = process.env.FEISHU_APP_SECRET;
const DOMAIN = process.env.FEISHU_DOMAIN || lark.Domain.Feishu;

function emit(obj) {
    process.stdout.write(JSON.stringify(obj) + '\n');
}

function fatal(msg) {
    emit({ type: 'error', message: msg });
    process.exit(1);
}

if (!APP_ID || !APP_SECRET) {
    fatal('FEISHU_APP_ID and FEISHU_APP_SECRET env vars are required');
}

// Forward every lark event to ESR as a JSON line. ESR's Elixir-side
// Port reader parses one line at a time.
const eventDispatcher = new lark.EventDispatcher({}).register({
    'im.message.receive_v1': async (data) => {
        // SDK strips schema/header wrapping; re-wrap so ESR's existing
        // build_message_body code reads the same shape it did from
        // HTTP webhook events.
        emit({
            type: 'event',
            schema: '2.0',
            header: { event_type: 'im.message.receive_v1' },
            event: data,
        });
    },
    'im.message.reaction.created_v1': async (data) => {
        emit({
            type: 'event',
            schema: '2.0',
            header: { event_type: 'im.message.reaction.created_v1' },
            event: data,
        });
    },
});

const wsClient = new lark.WSClient({
    appId: APP_ID,
    appSecret: APP_SECRET,
    domain: DOMAIN,
    loggerLevel: lark.LoggerLevel.warn,
});

emit({ type: 'sidecar_starting' });

wsClient
    .start({ eventDispatcher })
    .then(() => emit({ type: 'connected' }))
    .catch((err) => {
        emit({ type: 'error', message: String(err && err.message ? err.message : err) });
        process.exit(1);
    });

process.on('SIGINT', () => {
    emit({ type: 'disconnected', reason: 'sigint' });
    try { wsClient.close({ force: true }); } catch (_) {}
    process.exit(0);
});

process.on('SIGTERM', () => {
    emit({ type: 'disconnected', reason: 'sigterm' });
    try { wsClient.close({ force: true }); } catch (_) {}
    process.exit(0);
});

// Keep the process alive (the SDK manages its own WS loop).
setInterval(() => {}, 60_000);
