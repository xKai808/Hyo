// api/_hq-store.js — shared in-memory state for HQ dashboard
// Underscore prefix = Vercel will NOT deploy this as an endpoint.
// Data lives in the lambda's memory. Warm invocations share it.
// Cold start = empty state until the Mini pushes again.
// v1: swap globalThis.__hq for Vercel KV with zero API changes.

if (!globalThis.__hq) {
  globalThis.__hq = {
    events: [],     // { ts, agent, msg }  — last 100
    ra: {},         // { lastRun, lastBrief, wordCount, sourceCount, status }
    aurora: {},     // { subscribers: [], lastSend }
    sentinel: {},   // { lastRun, passed, failed, issues }
    cipher: {},     // { lastRun, secretsDir, founderToken, leaks }
    sim: {},        // { lastRun, briefs, errors, wallTime, report }
    consolidation: {},  // { lastRun, briefSynced, tasksSynced }
    aether: {},  // { lastRun, status }
    health: {},     // { apiOk, tokenOk, deployOk }
  };
}

export function getStore() {
  return globalThis.__hq;
}

export function pushEvent(agent, msg) {
  const store = getStore();
  store.events.unshift({
    ts: new Date().toISOString(),
    agent,
    msg,
  });
  // keep last 100
  if (store.events.length > 100) store.events.length = 100;
}

export function updateSection(section, data) {
  const store = getStore();
  if (store[section]) {
    Object.assign(store[section], data);
  }
}
