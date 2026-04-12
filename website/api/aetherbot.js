// /api/aetherbot — Aetherbot trade ingestion + metrics API
//
// Routes (via ?action= query param):
//   POST ?action=trade    { trade }        → records a trade (founder-token gated)
//   POST ?action=metrics  { metrics }      → bulk metrics update (founder-token gated)
//   GET  ?action=metrics                   → returns current metrics (public)
//   GET  (no action)                       → returns service status

// ─── In-memory metrics store ───
if (!globalThis.__aetherbot) {
  globalThis.__aetherbot = {
    currentWeek: {
      start: "", end: "",
      startingBalance: 1000, currentBalance: 1000,
      pnl: 0, pnlPercent: 0,
      trades: 0, wins: 0, losses: 0, winRate: 0,
      stoplossTriggers: 0, harvestEvents: 0,
      strategies: [], dailyPnl: [], recentTrades: [],
    },
    lastWeek: {},
    allTimeStats: { totalPnl: 0, totalTrades: 0, weeklyHistory: [] },
    updatedAt: new Date().toISOString(),
  };
}

function getStore() { return globalThis.__aetherbot; }

function mtnNow() {
  return new Date().toLocaleString("sv-SE", { timeZone: "America/Denver" }).replace(" ", "T") + "-06:00";
}

function todayMTN() {
  return new Date().toLocaleDateString("sv-SE", { timeZone: "America/Denver" });
}

// ─── Trade recording logic (mirrors aetherbot.sh) ───
function recordTrade(trade) {
  const store = getStore();
  const cw = store.currentWeek;
  const pnl = parseFloat(trade.pnl || 0);
  const isWin = pnl > 0;

  cw.trades += 1;
  cw.pnl = Math.round((cw.pnl + pnl) * 100) / 100;
  cw.currentBalance = Math.round((cw.startingBalance + cw.pnl) * 100) / 100;
  cw.pnlPercent = cw.startingBalance ? Math.round((cw.pnl / cw.startingBalance) * 10000) / 100 : 0;

  if (isWin) cw.wins += 1;
  else cw.losses += 1;
  cw.winRate = cw.trades ? Math.round((cw.wins / cw.trades) * 1000) / 10 : 0;

  if (trade.type === "stoploss") cw.stoplossTriggers += 1;
  if (trade.type === "harvest") cw.harvestEvents += 1;

  // Update daily PNL
  const today = todayMTN();
  const dayEntry = cw.dailyPnl.find(d => d.date === today);
  if (dayEntry) {
    dayEntry.pnl = Math.round((dayEntry.pnl + pnl) * 100) / 100;
    dayEntry.balance = cw.currentBalance;
    dayEntry.trades += 1;
  }

  // Update strategy
  if (trade.strategy) {
    const strat = cw.strategies.find(s => s.name.toLowerCase() === trade.strategy.toLowerCase());
    if (strat) {
      strat.pnl = Math.round((strat.pnl + pnl) * 100) / 100;
      strat.trades += 1;
      strat.lastAction = mtnNow();
      if (pnl > 0) strat.status = "active";
    }
  }

  // Add to recent trades (cap at 50)
  cw.recentTrades.unshift({
    ts: mtnNow(),
    side: trade.side || "—",
    pair: trade.pair || "—",
    price: trade.price || 0,
    qty: trade.qty || 0,
    pnl: pnl,
    strategy: trade.strategy || "",
    type: trade.type || "market",
  });
  if (cw.recentTrades.length > 50) cw.recentTrades.length = 50;

  store.updatedAt = mtnNow();
  return { ok: true, balance: cw.currentBalance, pnl: cw.pnl, trades: cw.trades };
}

// ─── Handler ───
export default function handler(req, res) {
  const action = req.query.action || "";

  // ── Record trade (founder-token gated) ──
  if (action === "trade" && req.method === "POST") {
    const token = req.headers["x-founder-token"] || req.headers["authorization"]?.replace("Bearer ", "");
    if (token !== process.env.HYO_FOUNDER_TOKEN) {
      return res.status(401).json({ ok: false, error: "unauthorized" });
    }
    const { trade } = req.body || {};
    if (!trade || !trade.pair) {
      return res.status(400).json({ ok: false, error: "missing trade data (need at minimum: {pair, pnl})" });
    }
    const result = recordTrade(trade);
    return res.status(200).json(result);
  }

  // ── Bulk metrics update (founder-token gated) ──
  if (action === "metrics" && req.method === "POST") {
    const token = req.headers["x-founder-token"] || req.headers["authorization"]?.replace("Bearer ", "");
    if (token !== process.env.HYO_FOUNDER_TOKEN) {
      return res.status(401).json({ ok: false, error: "unauthorized" });
    }
    const { metrics } = req.body || {};
    if (!metrics) {
      return res.status(400).json({ ok: false, error: "missing metrics object" });
    }
    // Merge incoming metrics into store
    const store = getStore();
    if (metrics.currentWeek) Object.assign(store.currentWeek, metrics.currentWeek);
    if (metrics.lastWeek) Object.assign(store.lastWeek, metrics.lastWeek);
    if (metrics.allTimeStats) Object.assign(store.allTimeStats, metrics.allTimeStats);
    store.updatedAt = mtnNow();
    return res.status(200).json({ ok: true, ts: store.updatedAt });
  }

  // ── Get metrics (public) ──
  if (action === "metrics" && req.method === "GET") {
    return res.status(200).json({ ok: true, ...getStore() });
  }

  // ── Fallback ──
  if (req.method === "GET" && !action) {
    const store = getStore();
    return res.status(200).json({
      ok: true,
      service: "aetherbot",
      trades: store.currentWeek.trades,
      balance: store.currentWeek.currentBalance,
      updatedAt: store.updatedAt,
    });
  }

  return res.status(400).json({ ok: false, error: "unknown action" });
}
