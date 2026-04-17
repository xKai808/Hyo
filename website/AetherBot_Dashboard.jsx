import { useState } from "react";

// ─── DATA ────────────────────────────────────────────────────────────────────

const STRATEGY_DATA = [
  {
    name: "PAQ_EARLY_AGG",
    trades: 50, wins: 37, losses: 13,
    net: 66.46, avgWin: 3.42, avgLoss: -2.18,
    status: "ACTIVE",
    note: "High-variance earner"
  },
  {
    name: "bps_premium",
    trades: 50, wins: 35, losses: 15,
    net: 3.03, avgWin: 1.68, avgLoss: -4.01,
    status: "WATCH",
    note: "Evening volatile Apr 16"
  },
  {
    name: "PAQ_STRUCT_GATE",
    trades: 9, wins: 3, losses: 6,
    net: -8.84, avgWin: 6.10, avgLoss: -5.52,
    status: "ALERT",
    note: "33% WR — 3-session cold streak"
  },
  {
    name: "bps_late",
    trades: 4, wins: 4, losses: 0,
    net: 2.98, avgWin: 0.75, avgLoss: 0,
    status: "ACTIVE",
    note: "Perfect — small sample"
  },
  {
    name: "WES_EARLY",
    trades: 3, wins: 2, losses: 1,
    net: 2.08, avgWin: 1.54, avgLoss: -1.00,
    status: "MONITOR",
    note: "New — watching"
  },
  {
    name: "BCDP_FAST_COMMIT",
    trades: 1, wins: 1, losses: 0,
    net: 1.02, avgWin: 1.02, avgLoss: 0,
    status: "MONITOR",
    note: "New — 1 trade only"
  },
];

const SESSION_DATA = [
  {
    session: "NY_PRIME",
    window: "09:00 – 15:00",
    trades: 28, wins: 19, losses: 9,
    net: 40.16,
    byDay: [1.26, 15.23, 24.02, -0.35],
    note: "Profit engine — protect"
  },
  {
    session: "ASIA_OPEN",
    window: "00:00 – 03:00",
    trades: 14, wins: 10, losses: 4,
    net: 14.50,
    byDay: [0, 5.04, 9.00, 0],
    note: "Consistent small wins"
  },
  {
    session: "EVENING",
    window: "17:00 – 22:00",
    trades: 24, wins: 14, losses: 10,
    net: 9.65,
    byDay: [18.28, 9.22, -3.87, -13.98],
    note: "⚠ Apr 16 BTC regime — 1 session"
  },
  {
    session: "EU_MORNING",
    window: "03:00 – 05:00",
    trades: 12, wins: 7, losses: 5,
    net: 3.77,
    byDay: [0, 1.41, -1.25, 3.61],
    note: "Monitor post-04:15 losses"
  },
  {
    session: "NY_OPEN",
    window: "07:00 – 09:00",
    trades: 3, wins: 2, losses: 1,
    net: 1.20,
    byDay: [0, 0, 0, 1.20],
    note: "Limited data"
  },
  {
    session: "OVERNIGHT",
    window: "22:00 – 00:00",
    trades: 5, wins: 2, losses: 3,
    net: -3.10,
    byDay: [-3.10, 0, 0, 0],
    note: "Historical bleeder — low priority"
  },
];

const DAILY_REPORTS = [
  {
    date: "Apr 16", day: "WED",
    open: 116.16, close: 113.96,
    net: -2.20, trades: 26,
    status: "ACTIVE",
    highlight: "PAQ_EARLY_AGG +$19.27 (47c) offset -$14.96 loss. Evening bps bleed.",
    issues: ["POS WARNING fired (API 0 local 15)", "FLIP_EMERGENCY on 34c position"],
    version: "v253"
  },
  {
    date: "Apr 15", day: "TUE",
    open: 108.91, close: 115.79,
    net: 6.88, trades: 38,
    status: "CONFIRMED",
    highlight: "NY_PRIME dominated: 30c/36c/35c PAQ_AGG wins +$26.51. PAQ_STRUCT -$11.88.",
    issues: ["Harvest Mode B (BDI 1112, ABSENT bids)", "PAQ_STRUCT_GATE 0W/2L in session"],
    version: "v253"
  },
  {
    date: "Apr 14", day: "MON",
    open: 86.44, close: 108.91,
    net: 22.47, trades: 29,
    status: "CONFIRMED",
    highlight: "Best day. PAQ_STRUCT_GATE +$8.43 carry (20c). WES_EARLY +$2.28.",
    issues: ["BDI=0 hold on 00:45 bps stop"],
    version: "v253"
  },
  {
    date: "Apr 13", day: "SUN",
    open: 90.25, close: 86.44,
    net: -3.81, trades: 25,
    status: "CONFIRMED",
    highlight: "bps_premium -$12.96 (10:15 MTN) defined the day. Evening recovered +$20+.",
    issues: ["BDI=0 hold staged exit failure (18c position)", "Harvest ABSENT bids confirmed"],
    version: "v253"
  },
];

const OPEN_ISSUES = [
  { id: 1, priority: "P0", label: "Harvest Mode B — stale orderbook (ABSENT bids on deep book)", target: "v254" },
  { id: 2, priority: "P1", label: "BDI=0 hold — no time gate (fires at <120s, causes expiry losses)", target: "v254" },
  { id: 3, priority: "P1", label: "POS WARNING — API 0 vs local N during exit sequences", target: "v254" },
  { id: 4, priority: "P2", label: "EU_MORNING post-04:15 losses clustering", target: "Monitor" },
  { id: 5, priority: "P3", label: "Weekend risk profile ($5 flat, PAQ_MIN=4, disable confirm)", target: "Pending" },
];

// ─── HELPERS ─────────────────────────────────────────────────────────────────

const fmt = (n, prefix = "$") =>
  n == null ? "—" : `${n >= 0 ? "+" : ""}${prefix}${Math.abs(n).toFixed(2)}`;

const pct = (wins, total) =>
  total === 0 ? "—" : `${Math.round((wins / total) * 100)}%`;

const statusColor = {
  ACTIVE:  { bg: "#0d2d1a", border: "#00ff88", text: "#00ff88" },
  WATCH:   { bg: "#2d2200", border: "#ffa500", text: "#ffa500" },
  ALERT:   { bg: "#2d0d0d", border: "#ff4444", text: "#ff4444" },
  MONITOR: { bg: "#0d1a2d", border: "#00c8ff", text: "#00c8ff" },
};

const priorityColor = {
  P0: "#ff4444",
  P1: "#ff8c44",
  P2: "#ffa500",
  P3: "#888888",
};

// ─── SUB-COMPONENTS ──────────────────────────────────────────────────────────

function WRBar({ wins, total }) {
  const wr = total === 0 ? 0 : (wins / total) * 100;
  const color = wr >= 75 ? "#00ff88" : wr >= 60 ? "#ffa500" : "#ff4444";
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
      <div style={{
        width: 80, height: 6, background: "#1a1a1a", borderRadius: 3, overflow: "hidden"
      }}>
        <div style={{ width: `${wr}%`, height: "100%", background: color, borderRadius: 3,
          transition: "width 0.6s ease" }} />
      </div>
      <span style={{ color, fontFamily: "monospace", fontSize: 12 }}>{Math.round(wr)}%</span>
    </div>
  );
}

function StatusBadge({ status }) {
  const c = statusColor[status] || statusColor.MONITOR;
  return (
    <span style={{
      padding: "2px 8px", borderRadius: 3, fontSize: 10, fontWeight: 700,
      letterSpacing: "0.08em", fontFamily: "monospace",
      background: c.bg, border: `1px solid ${c.border}`, color: c.text
    }}>
      {status}
    </span>
  );
}

function NetCell({ value }) {
  const color = value > 0 ? "#00ff88" : value < 0 ? "#ff4444" : "#888";
  return (
    <span style={{ color, fontFamily: "monospace", fontWeight: 700, fontSize: 13 }}>
      {fmt(value)}
    </span>
  );
}

function MiniSparkline({ data }) {
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const W = 60, H = 20;
  const pts = data.map((v, i) => {
    const x = (i / (data.length - 1)) * W;
    const y = H - ((v - min) / range) * H;
    return `${x},${y}`;
  }).join(" ");
  return (
    <svg width={W} height={H} style={{ overflow: "visible" }}>
      <polyline points={pts} fill="none" stroke="#00ff8866" strokeWidth={1.5} />
      {data.map((v, i) => {
        const x = (i / (data.length - 1)) * W;
        const y = H - ((v - min) / range) * H;
        return <circle key={i} cx={x} cy={y} r={2}
          fill={v >= 0 ? "#00ff88" : "#ff4444"} />;
      })}
    </svg>
  );
}

function DayFeedCard({ report, isSelected, onClick }) {
  const isPos = report.net >= 0;
  const isActive = report.status === "ACTIVE";
  return (
    <div onClick={onClick} style={{
      background: isSelected ? "#1a1a1a" : "#111",
      border: `1px solid ${isSelected ? "#333" : "#1f1f1f"}`,
      borderRadius: 6, padding: "12px 14px", cursor: "pointer",
      transition: "all 0.2s", marginBottom: 8,
      borderLeft: `3px solid ${isActive ? "#00c8ff" : isPos ? "#00ff88" : "#ff4444"}`
    }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <div>
          <span style={{ color: "#888", fontFamily: "monospace", fontSize: 11 }}>
            {report.day} ·
          </span>
          <span style={{ color: "#ccc", fontFamily: "monospace", fontSize: 11, marginLeft: 4 }}>
            {report.date}
          </span>
          {isActive && (
            <span style={{
              marginLeft: 8, fontSize: 9, fontWeight: 700, letterSpacing: "0.1em",
              color: "#00c8ff", border: "1px solid #00c8ff33", borderRadius: 2,
              padding: "1px 5px", fontFamily: "monospace"
            }}>LIVE</span>
          )}
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{
            color: isPos ? "#00ff88" : "#ff4444",
            fontFamily: "monospace", fontWeight: 700, fontSize: 14
          }}>
            {fmt(report.net)}
          </div>
          <div style={{ color: "#555", fontSize: 10, fontFamily: "monospace" }}>
            {report.trades} trades
          </div>
        </div>
      </div>
      {isSelected && (
        <div style={{ marginTop: 10, paddingTop: 10, borderTop: "1px solid #222" }}>
          <div style={{ color: "#aaa", fontSize: 11, lineHeight: 1.5, marginBottom: 8 }}>
            {report.highlight}
          </div>
          <div style={{ display: "flex", gap: 16, marginBottom: 8 }}>
            <div>
              <div style={{ color: "#555", fontSize: 10, fontFamily: "monospace" }}>OPEN</div>
              <div style={{ color: "#888", fontFamily: "monospace", fontSize: 12 }}>
                ${report.open}
              </div>
            </div>
            <div>
              <div style={{ color: "#555", fontSize: 10, fontFamily: "monospace" }}>CLOSE</div>
              <div style={{ color: "#888", fontFamily: "monospace", fontSize: 12 }}>
                ${report.close}
              </div>
            </div>
            <div>
              <div style={{ color: "#555", fontSize: 10, fontFamily: "monospace" }}>VERSION</div>
              <div style={{ color: "#00c8ff", fontFamily: "monospace", fontSize: 12 }}>
                {report.version}
              </div>
            </div>
          </div>
          {report.issues.length > 0 && (
            <div>
              <div style={{ color: "#555", fontSize: 10, fontFamily: "monospace", marginBottom: 4 }}>
                FLAGGED
              </div>
              {report.issues.map((iss, i) => (
                <div key={i} style={{
                  color: "#ffa500", fontSize: 10, fontFamily: "monospace",
                  display: "flex", alignItems: "flex-start", gap: 6, marginBottom: 2
                }}>
                  <span style={{ color: "#555", marginTop: 1 }}>▸</span>
                  <span>{iss}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ─── MAIN COMPONENT ───────────────────────────────────────────────────────────

export default function AetherBotDashboard() {
  const [selectedDay, setSelectedDay] = useState(0);
  const [stratSort, setStratSort] = useState("net");
  const [sessionSort, setSessionSort] = useState("net");

  const totalNet = 25.54;
  const currentBalance = 113.96;
  const startBalance = 86.44;
  const totalTrades = STRATEGY_DATA.reduce((s, d) => s + d.trades, 0);
  const totalWins = STRATEGY_DATA.reduce((s, d) => s + d.wins, 0);
  const overallWR = Math.round((totalWins / totalTrades) * 100);
  const targetDaily = 100;
  const daysTracked = 4;

  const sortedStrats = [...STRATEGY_DATA].sort((a, b) => {
    if (stratSort === "net") return b.net - a.net;
    if (stratSort === "wr") return (b.wins / b.trades) - (a.wins / a.trades);
    if (stratSort === "trades") return b.trades - a.trades;
    return 0;
  });

  const sortedSessions = [...SESSION_DATA].sort((a, b) => {
    if (sessionSort === "net") return b.net - a.net;
    if (sessionSort === "wr") return (b.wins / b.trades) - (a.wins / a.trades);
    return 0;
  });

  const colStyle = (key, current) => ({
    cursor: "pointer",
    color: current === key ? "#00c8ff" : "#555",
    fontSize: 10,
    fontFamily: "monospace",
    letterSpacing: "0.06em",
    userSelect: "none",
    padding: "0 4px",
    transition: "color 0.2s"
  });

  const TH = ({ label, sortKey, current, onSort }) => (
    <th style={{ padding: "8px 10px", textAlign: "left", fontWeight: 400,
      borderBottom: "1px solid #1f1f1f" }}>
      <span style={colStyle(sortKey, current)} onClick={() => onSort(sortKey)}>
        {label} {current === sortKey ? "↓" : ""}
      </span>
    </th>
  );

  return (
    <div style={{
      background: "#0d0d0d", minHeight: "100vh", color: "#e0e0e0",
      fontFamily: "'Space Mono', 'Courier New', monospace",
      padding: "24px", boxSizing: "border-box"
    }}>

      {/* ── HEADER ── */}
      <div style={{
        display: "flex", justifyContent: "space-between", alignItems: "flex-start",
        marginBottom: 24, paddingBottom: 20, borderBottom: "1px solid #1f1f1f"
      }}>
        <div>
          <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
            <h1 style={{
              margin: 0, fontSize: 22, fontWeight: 700, letterSpacing: "0.05em",
              color: "#00c8ff", fontFamily: "monospace"
            }}>
              AETHERBOT
            </h1>
            <span style={{ color: "#333", fontSize: 14 }}>v253</span>
            <span style={{
              fontSize: 9, fontWeight: 700, letterSpacing: "0.15em",
              color: "#00ff88", border: "1px solid #00ff8844",
              padding: "2px 8px", borderRadius: 2
            }}>RUNNING</span>
          </div>
          <div style={{ color: "#555", fontSize: 11, marginTop: 4 }}>
            Kalshi · KXBTC15M · Weekly Dashboard · Apr 13–16, 2026 · MTN
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: "#00ff88", letterSpacing: "-0.02em" }}>
            ${currentBalance.toFixed(2)}
          </div>
          <div style={{ color: "#555", fontSize: 11 }}>current balance</div>
        </div>
      </div>

      {/* ── KEY METRICS ROW ── */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(5, 1fr)",
        gap: 12, marginBottom: 24
      }}>
        {[
          { label: "4-DAY NET", value: fmt(totalNet), color: totalNet >= 0 ? "#00ff88" : "#ff4444" },
          { label: "OVERALL WR", value: `${overallWR}%`, color: overallWR >= 70 ? "#00ff88" : "#ffa500" },
          { label: "TOTAL TRADES", value: totalTrades, color: "#e0e0e0" },
          { label: "DAILY TARGET", value: "$100 / day", color: "#555" },
          { label: "OPEN ISSUES", value: OPEN_ISSUES.length, color: "#ff8c44" },
        ].map(m => (
          <div key={m.label} style={{
            background: "#111", border: "1px solid #1f1f1f",
            borderRadius: 6, padding: "14px 16px"
          }}>
            <div style={{ color: "#555", fontSize: 9, letterSpacing: "0.1em", marginBottom: 6 }}>
              {m.label}
            </div>
            <div style={{ fontSize: 20, fontWeight: 700, color: m.color }}>
              {m.value}
            </div>
          </div>
        ))}
      </div>

      {/* ── MAIN GRID ── */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 320px", gap: 16 }}>

        {/* LEFT COLUMN */}
        <div>

          {/* STRATEGY TABLE */}
          <div style={{
            background: "#111", border: "1px solid #1f1f1f",
            borderRadius: 6, marginBottom: 16, overflow: "hidden"
          }}>
            <div style={{
              padding: "14px 16px", borderBottom: "1px solid #1f1f1f",
              display: "flex", justifyContent: "space-between", alignItems: "center"
            }}>
              <div>
                <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.1em", color: "#888" }}>
                  STRATEGY PERFORMANCE
                </span>
                <span style={{ color: "#333", fontSize: 10, marginLeft: 8 }}>
                  4-day window · click headers to sort
                </span>
              </div>
              <span style={{ color: "#333", fontSize: 10 }}>
                {STRATEGY_DATA.reduce((s,d) => s+d.trades,0)} trades total
              </span>
            </div>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
              <thead style={{ background: "#0d0d0d" }}>
                <tr>
                  <TH label="FAMILY" sortKey="name" current={stratSort} onSort={setStratSort} />
                  <TH label="TRADES" sortKey="trades" current={stratSort} onSort={setStratSort} />
                  <TH label="WIN RATE" sortKey="wr" current={stratSort} onSort={setStratSort} />
                  <th style={{ padding: "8px 10px", textAlign: "left", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f", color: "#555", fontSize: 10,
                    letterSpacing: "0.06em" }}>AVG WIN</th>
                  <th style={{ padding: "8px 10px", textAlign: "left", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f", color: "#555", fontSize: 10,
                    letterSpacing: "0.06em" }}>AVG LOSS</th>
                  <TH label="NET P&L" sortKey="net" current={stratSort} onSort={setStratSort} />
                  <th style={{ padding: "8px 10px", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f" }}></th>
                  <th style={{ padding: "8px 10px", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f" }}></th>
                </tr>
              </thead>
              <tbody>
                {sortedStrats.map((s, i) => (
                  <tr key={s.name} style={{
                    background: i % 2 === 0 ? "transparent" : "#0d0d0d",
                    borderBottom: "1px solid #161616"
                  }}>
                    <td style={{ padding: "10px 10px" }}>
                      <div style={{ fontFamily: "monospace", fontSize: 12, color: "#ddd",
                        fontWeight: 600 }}>
                        {s.name}
                      </div>
                      <div style={{ color: "#444", fontSize: 10, marginTop: 2 }}>
                        {s.note}
                      </div>
                    </td>
                    <td style={{ padding: "10px 10px" }}>
                      <div style={{ color: "#888", fontFamily: "monospace", fontSize: 12 }}>
                        {s.trades}
                      </div>
                      <div style={{ color: "#444", fontSize: 10 }}>
                        {s.wins}W / {s.losses}L
                      </div>
                    </td>
                    <td style={{ padding: "10px 10px" }}>
                      <WRBar wins={s.wins} total={s.trades} />
                    </td>
                    <td style={{ padding: "10px 10px" }}>
                      <span style={{ color: "#00ff8899", fontFamily: "monospace", fontSize: 12 }}>
                        +${s.avgWin.toFixed(2)}
                      </span>
                    </td>
                    <td style={{ padding: "10px 10px" }}>
                      <span style={{ color: s.avgLoss < 0 ? "#ff444499" : "#888",
                        fontFamily: "monospace", fontSize: 12 }}>
                        {s.avgLoss < 0 ? `-$${Math.abs(s.avgLoss).toFixed(2)}` : "—"}
                      </span>
                    </td>
                    <td style={{ padding: "10px 10px" }}>
                      <NetCell value={s.net} />
                    </td>
                    <td style={{ padding: "10px 10px" }}>
                      <StatusBadge status={s.status} />
                    </td>
                    <td style={{ padding: "10px 10px", width: 70 }}>
                      {s.trades >= 2 && (
                        <div style={{ opacity: 0.7 }}>
                          <MiniSparkline data={
                            DAILY_REPORTS.slice().reverse().map(d => {
                              if (s.name === "PAQ_EARLY_AGG")
                                return [22.44, 4.15, 26.51, 13.36][DAILY_REPORTS.slice().reverse().indexOf(d)] || 0;
                              if (s.name === "bps_premium")
                                return [0.52, 8.00, 9.33, -14.82][DAILY_REPORTS.slice().reverse().indexOf(d)] || 0;
                              if (s.name === "PAQ_STRUCT_GATE")
                                return [3.57, 8.18, -11.88, -8.71][DAILY_REPORTS.slice().reverse().indexOf(d)] || 0;
                              return [s.net / 4, s.net / 4, s.net / 4, s.net / 4][0];
                            })
                          } />
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr style={{ background: "#0a0a0a", borderTop: "1px solid #252525" }}>
                  <td style={{ padding: "10px 10px", color: "#666", fontSize: 11 }}>TOTAL</td>
                  <td style={{ padding: "10px 10px", color: "#888", fontFamily: "monospace", fontSize: 12 }}>
                    {totalTrades}
                  </td>
                  <td style={{ padding: "10px 10px" }}>
                    <WRBar wins={totalWins} total={totalTrades} />
                  </td>
                  <td colSpan={2}></td>
                  <td style={{ padding: "10px 10px" }}>
                    <NetCell value={STRATEGY_DATA.reduce((s, d) => s + d.net, 0)} />
                  </td>
                  <td colSpan={2}></td>
                </tr>
              </tfoot>
            </table>
          </div>

          {/* SESSION TABLE */}
          <div style={{
            background: "#111", border: "1px solid #1f1f1f",
            borderRadius: 6, overflow: "hidden"
          }}>
            <div style={{
              padding: "14px 16px", borderBottom: "1px solid #1f1f1f",
              display: "flex", justifyContent: "space-between", alignItems: "center"
            }}>
              <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.1em", color: "#888" }}>
                SESSION WINDOWS · MTN
              </span>
              <span style={{ color: "#333", fontSize: 10 }}>click headers to sort</span>
            </div>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
              <thead style={{ background: "#0d0d0d" }}>
                <tr>
                  <TH label="SESSION" sortKey="name" current={sessionSort} onSort={setSessionSort} />
                  <th style={{ padding: "8px 10px", textAlign: "left", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f", color: "#555", fontSize: 10 }}>WINDOW</th>
                  <TH label="TRADES" sortKey="trades" current={sessionSort} onSort={setSessionSort} />
                  <TH label="WIN RATE" sortKey="wr" current={sessionSort} onSort={setSessionSort} />
                  <TH label="NET P&L" sortKey="net" current={sessionSort} onSort={setSessionSort} />
                  <th style={{ padding: "8px 10px", textAlign: "left", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f", color: "#555", fontSize: 10 }}>
                    DAILY TREND (13→16)
                  </th>
                  <th style={{ padding: "8px 10px", textAlign: "left", fontWeight: 400,
                    borderBottom: "1px solid #1f1f1f", color: "#555", fontSize: 10 }}>NOTE</th>
                </tr>
              </thead>
              <tbody>
                {sortedSessions.map((s, i) => (
                  <tr key={s.session} style={{
                    background: i % 2 === 0 ? "transparent" : "#0d0d0d",
                    borderBottom: "1px solid #161616"
                  }}>
                    <td style={{ padding: "12px 10px" }}>
                      <div style={{ fontFamily: "monospace", fontSize: 12,
                        color: s.net > 10 ? "#00ff88" : s.net > 0 ? "#ddd" : "#ff4444",
                        fontWeight: 600 }}>
                        {s.session}
                      </div>
                    </td>
                    <td style={{ padding: "12px 10px" }}>
                      <span style={{ color: "#555", fontFamily: "monospace", fontSize: 11 }}>
                        {s.window}
                      </span>
                    </td>
                    <td style={{ padding: "12px 10px" }}>
                      <div style={{ color: "#888", fontFamily: "monospace", fontSize: 12 }}>
                        {s.trades}
                      </div>
                      <div style={{ color: "#444", fontSize: 10 }}>
                        {s.wins}W / {s.losses}L
                      </div>
                    </td>
                    <td style={{ padding: "12px 10px" }}>
                      <WRBar wins={s.wins} total={s.trades} />
                    </td>
                    <td style={{ padding: "12px 10px" }}>
                      <NetCell value={s.net} />
                    </td>
                    <td style={{ padding: "12px 10px" }}>
                      <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
                        {s.byDay.map((v, idx) => (
                          <div key={idx} style={{
                            width: 28, textAlign: "center",
                            fontSize: 9, fontFamily: "monospace",
                            color: v > 0 ? "#00ff88" : v < 0 ? "#ff4444" : "#333",
                            padding: "3px 2px", borderRadius: 2,
                            background: v > 0 ? "#00ff8811" : v < 0 ? "#ff444411" : "transparent",
                            border: `1px solid ${v > 0 ? "#00ff8822" : v < 0 ? "#ff444422" : "#1a1a1a"}`
                          }}>
                            {v === 0 ? "—" : (v > 0 ? "+" : "") + v.toFixed(0)}
                          </div>
                        ))}
                      </div>
                    </td>
                    <td style={{ padding: "12px 10px" }}>
                      <span style={{ color: "#555", fontSize: 11 }}>{s.note}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* OPEN ISSUES */}
          <div style={{
            background: "#111", border: "1px solid #1f1f1f",
            borderRadius: 6, marginTop: 16, overflow: "hidden"
          }}>
            <div style={{
              padding: "14px 16px", borderBottom: "1px solid #1f1f1f"
            }}>
              <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.1em", color: "#888" }}>
                OPEN ISSUES · v254 SCOPE
              </span>
            </div>
            <div style={{ padding: "8px 0" }}>
              {OPEN_ISSUES.map(issue => (
                <div key={issue.id} style={{
                  display: "flex", alignItems: "flex-start", gap: 12,
                  padding: "10px 16px", borderBottom: "1px solid #161616"
                }}>
                  <span style={{
                    fontSize: 10, fontWeight: 700, fontFamily: "monospace",
                    color: priorityColor[issue.priority],
                    minWidth: 24, paddingTop: 1
                  }}>
                    {issue.priority}
                  </span>
                  <span style={{ color: "#bbb", fontSize: 12, flex: 1, lineHeight: 1.4 }}>
                    {issue.label}
                  </span>
                  <span style={{
                    fontSize: 10, fontFamily: "monospace",
                    color: issue.target === "v254" ? "#00c8ff" : "#555",
                    minWidth: 50, textAlign: "right"
                  }}>
                    {issue.target}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN — DAILY FEED */}
        <div>
          <div style={{
            background: "#111", border: "1px solid #1f1f1f",
            borderRadius: 6, overflow: "hidden", marginBottom: 16
          }}>
            <div style={{
              padding: "14px 16px", borderBottom: "1px solid #1f1f1f"
            }}>
              <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.1em", color: "#888" }}>
                DAILY REPORT FEED
              </span>
            </div>
            <div style={{ padding: "12px" }}>
              {DAILY_REPORTS.map((r, i) => (
                <DayFeedCard
                  key={r.date}
                  report={r}
                  isSelected={selectedDay === i}
                  onClick={() => setSelectedDay(selectedDay === i ? null : i)}
                />
              ))}
            </div>
          </div>

          {/* BALANCE CURVE */}
          <div style={{
            background: "#111", border: "1px solid #1f1f1f",
            borderRadius: 6, padding: "14px 16px"
          }}>
            <div style={{
              fontSize: 11, fontWeight: 700, letterSpacing: "0.1em",
              color: "#888", marginBottom: 14
            }}>
              BALANCE LEDGER
            </div>
            {[
              { date: "Apr 7", bal: 104.02, confirmed: true },
              { date: "Apr 13", bal: 86.44, confirmed: true },
              { date: "Apr 14", bal: 108.91, confirmed: true },
              { date: "Apr 15", bal: 115.79, confirmed: false },
              { date: "Apr 16", bal: 113.96, confirmed: false, live: true },
            ].map((entry, i, arr) => {
              const prev = arr[i - 1]?.bal;
              const delta = prev != null ? entry.bal - prev : null;
              return (
                <div key={entry.date} style={{
                  display: "flex", justifyContent: "space-between",
                  alignItems: "center", padding: "8px 0",
                  borderBottom: "1px solid #161616"
                }}>
                  <div>
                    <span style={{ color: "#888", fontFamily: "monospace", fontSize: 12 }}>
                      {entry.date}
                    </span>
                    {entry.live && (
                      <span style={{
                        marginLeft: 6, fontSize: 9, color: "#00c8ff",
                        border: "1px solid #00c8ff33", padding: "1px 4px", borderRadius: 2
                      }}>LIVE</span>
                    )}
                    {!entry.confirmed && !entry.live && (
                      <span style={{
                        marginLeft: 6, fontSize: 9, color: "#555",
                        fontFamily: "monospace"
                      }}>est.</span>
                    )}
                  </div>
                  <div style={{ textAlign: "right" }}>
                    <div style={{ fontFamily: "monospace", fontSize: 13, color: "#ddd" }}>
                      ${entry.bal.toFixed(2)}
                    </div>
                    {delta != null && (
                      <div style={{
                        fontSize: 10, fontFamily: "monospace",
                        color: delta >= 0 ? "#00ff8888" : "#ff444488"
                      }}>
                        {delta >= 0 ? "+" : ""}${delta.toFixed(2)}
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
            <div style={{
              marginTop: 12, padding: "10px 0",
              borderTop: "1px solid #252525",
              display: "flex", justifyContent: "space-between"
            }}>
              <span style={{ color: "#555", fontSize: 11 }}>Target / day</span>
              <span style={{ color: "#555", fontFamily: "monospace", fontSize: 12 }}>$100.00</span>
            </div>
            <div style={{
              padding: "4px 0",
              display: "flex", justifyContent: "space-between"
            }}>
              <span style={{ color: "#555", fontSize: 11 }}>Next build</span>
              <span style={{ color: "#00c8ff", fontFamily: "monospace", fontSize: 12 }}>v254</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
