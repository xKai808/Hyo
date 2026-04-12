#!/usr/bin/env node
/**
 * hyo-mini-mcp — MCP server running on the Mac Mini.
 *
 * Exposes tools that Claude Cowork can call via the MCP connector.
 * This removes the sandbox bottleneck: Cowork calls a tool,
 * Mini executes the command, returns the result.
 *
 * Transport: stdio (for local Claude Code) or SSE (for remote Cowork connector).
 *
 * Usage:
 *   Local (Claude Code):  claude --mcp-server ./server.js
 *   Remote (Cowork):      node server.js --transport sse --port 3847
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { z } from "zod";
import { exec as execCb } from "child_process";
import { promisify } from "util";
import { readFile, writeFile, stat } from "fs/promises";
import { createServer } from "http";
import path from "path";

const exec = promisify(execCb);

// ─── Config ──────────────────────────────────────────────────────────────────
const HYO_ROOT = process.env.HYO_ROOT || path.join(process.env.HOME, "Documents", "Projects", "Hyo");
const AUTH_TOKEN = process.env.HYO_MCP_TOKEN || "";
const MAX_OUTPUT = 50_000;
const COMMAND_TIMEOUT = 60_000;

const BLOCKED_PATTERNS = [
  /\brm\s+-rf\s+[/~]/,
  /\bsudo\b/,
  /\bmkfs\b/,
  /\bdd\s+if=/,
  /\b(shutdown|reboot|halt)\b/,
  /\blaunchctl\s+bootout\b/,
];

// ─── Helpers ─────────────────────────────────────────────────────────────────
function truncate(str, max = MAX_OUTPUT) {
  if (!str || str.length <= max) return str || "";
  return str.slice(0, max) + `\n... [truncated at ${max} chars]`;
}

function isBlocked(cmd) {
  return BLOCKED_PATTERNS.some(p => p.test(cmd));
}

function mtnTimestamp() {
  return new Date().toLocaleString("en-US", { timeZone: "America/Denver" });
}

function reply(obj) {
  return { content: [{ type: "text", text: JSON.stringify(obj, null, 2) }] };
}

// ─── Server ──────────────────────────────────────────────────────────────────
const server = new McpServer({
  name: "hyo-mini",
  version: "1.0.0",
});

// ── Tool: execute_command ────────────────────────────────────────────────────
server.tool(
  "execute_command",
  "Run a shell command on the Mac Mini. Returns stdout, stderr, and exit code.",
  {
    command: z.string().describe("Shell command to execute"),
    cwd: z.string().optional().describe("Working directory (default: HYO_ROOT)"),
    timeout: z.number().optional().describe("Timeout in ms (default: 60000)"),
  },
  async ({ command, cwd, timeout }) => {
    if (isBlocked(command)) {
      return reply({ ok: false, error: "BLOCKED: command matched safety filter", command });
    }
    const dir = cwd || HYO_ROOT;
    const to = Math.min(timeout || COMMAND_TIMEOUT, 120_000);
    try {
      const { stdout, stderr } = await exec(command, {
        cwd: dir, timeout: to, maxBuffer: 5 * 1024 * 1024,
        env: { ...process.env, HYO_ROOT },
      });
      return reply({ ok: true, exit_code: 0, stdout: truncate(stdout), stderr: truncate(stderr), cwd: dir, ts: mtnTimestamp() });
    } catch (err) {
      return reply({ ok: false, exit_code: err.code || 1, stdout: truncate(err.stdout), stderr: truncate(err.stderr || err.message), cwd: dir, ts: mtnTimestamp() });
    }
  }
);

// ── Tool: git_push ───────────────────────────────────────────────────────────
server.tool(
  "git_push",
  "Push the Hyo repo to origin. Runs pre-deploy validation first.",
  {
    branch: z.string().optional().describe("Branch to push (default: main)"),
    force: z.boolean().optional().describe("Force push (default: false)"),
  },
  async ({ branch, force }) => {
    const br = branch || "main";
    if (force && br === "main") {
      return reply({ ok: false, error: "BLOCKED: force push to main is not allowed" });
    }
    try {
      const validate = await exec(`python3 bin/predeploy-validate.py`, { cwd: HYO_ROOT, timeout: 30_000, env: { ...process.env, HYO_ROOT } });
      if (validate.stderr && validate.stderr.includes("deploy blocked")) {
        return reply({ ok: false, step: "validation", stdout: truncate(validate.stdout), stderr: truncate(validate.stderr) });
      }
      const cmd = force ? `git push --force origin ${br}` : `git push origin ${br}`;
      const { stdout, stderr } = await exec(cmd, { cwd: HYO_ROOT, timeout: 60_000 });
      return reply({ ok: true, action: `git push origin ${br}`, stdout: truncate(stdout), stderr: truncate(stderr), ts: mtnTimestamp() });
    } catch (err) {
      return reply({ ok: false, action: `git push origin ${br}`, error: err.message, stdout: truncate(err.stdout), stderr: truncate(err.stderr), ts: mtnTimestamp() });
    }
  }
);

// ── Tool: deploy ─────────────────────────────────────────────────────────────
server.tool(
  "deploy",
  "Full deploy pipeline: pre-deploy validation → git push → wait → health check.",
  {
    message: z.string().optional().describe("What triggered this deploy"),
  },
  async ({ message }) => {
    const steps = [];
    try {
      const v = await exec(`python3 bin/predeploy-validate.py`, { cwd: HYO_ROOT, timeout: 30_000, env: { ...process.env, HYO_ROOT } });
      steps.push({ step: "validate", ok: true, output: truncate(v.stdout) });

      const p = await exec(`git push origin main`, { cwd: HYO_ROOT, timeout: 60_000 });
      steps.push({ step: "git_push", ok: true, output: truncate(p.stderr || p.stdout) });

      await new Promise(r => setTimeout(r, 10_000));

      const h = await exec(`curl -sf https://www.hyo.world/api/health`, { timeout: 15_000 });
      steps.push({ step: "health_check", ok: true, output: truncate(h.stdout) });

      return reply({ ok: true, message: message || "manual", steps, ts: mtnTimestamp() });
    } catch (err) {
      steps.push({ step: "failed", ok: false, error: err.message });
      return reply({ ok: false, message: message || "manual", steps, ts: mtnTimestamp() });
    }
  }
);

// ── Tool: read_file ──────────────────────────────────────────────────────────
server.tool(
  "read_file",
  "Read a file from the Hyo project directory.",
  {
    path: z.string().describe("Relative path from HYO_ROOT (e.g., 'KAI_BRIEF.md')"),
  },
  async ({ path: filePath }) => {
    try {
      const full = path.resolve(HYO_ROOT, filePath);
      if (!full.startsWith(HYO_ROOT)) {
        return reply({ ok: false, error: "BLOCKED: path escapes project directory" });
      }
      const content = await readFile(full, "utf-8");
      return { content: [{ type: "text", text: truncate(content) }] };
    } catch (err) {
      return reply({ ok: false, error: `Read failed: ${err.message}` });
    }
  }
);

// ── Tool: write_file ─────────────────────────────────────────────────────────
server.tool(
  "write_file",
  "Write content to a file in the Hyo project directory.",
  {
    path: z.string().describe("Relative path from HYO_ROOT"),
    content: z.string().describe("File content to write"),
  },
  async ({ path: filePath, content }) => {
    try {
      const full = path.resolve(HYO_ROOT, filePath);
      if (!full.startsWith(HYO_ROOT)) {
        return reply({ ok: false, error: "BLOCKED: path escapes project directory" });
      }
      await writeFile(full, content, "utf-8");
      const s = await stat(full);
      return reply({ ok: true, path: filePath, bytes: s.size, ts: mtnTimestamp() });
    } catch (err) {
      return reply({ ok: false, error: `Write failed: ${err.message}` });
    }
  }
);

// ── Tool: kai ────────────────────────────────────────────────────────────────
server.tool(
  "kai",
  "Run a kai.sh subcommand (e.g., 'health', 'verify', 'validate', 'gitpush').",
  {
    subcommand: z.string().describe("Kai subcommand (e.g., 'health', 'verify', 'deploy')"),
    args: z.string().optional().describe("Additional arguments"),
  },
  async ({ subcommand, args }) => {
    const cmd = `bash bin/kai.sh ${subcommand} ${args || ""}`.trim();
    try {
      const { stdout, stderr } = await exec(cmd, { cwd: HYO_ROOT, timeout: 120_000, env: { ...process.env, HYO_ROOT } });
      return reply({ ok: true, command: `kai ${subcommand}`, stdout: truncate(stdout), stderr: truncate(stderr), ts: mtnTimestamp() });
    } catch (err) {
      return reply({ ok: false, command: `kai ${subcommand}`, error: err.message, stdout: truncate(err.stdout), stderr: truncate(err.stderr), ts: mtnTimestamp() });
    }
  }
);

// ── Tool: ledger_query ───────────────────────────────────────────────────────
// Query the dispatch ledger — answer "what happened with task X?" questions.
server.tool(
  "ledger_query",
  "Query the dispatch ledger. Search tasks by ID, agent, status, or keyword. Returns matching entries with full lifecycle.",
  {
    query: z.string().describe("Search term: task ID (e.g., 'sam-001'), agent name (e.g., 'nel'), status (e.g., 'DONE'), or keyword"),
    limit: z.number().optional().describe("Max entries to return (default: 20)"),
  },
  async ({ query, limit }) => {
    const maxResults = limit || 20;
    try {
      const logPath = path.join(HYO_ROOT, "kai", "ledger", "log.jsonl");
      const raw = await readFile(logPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);
      const entries = lines.map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);

      const q = query.toLowerCase();
      const matched = entries.filter(e => {
        const str = JSON.stringify(e).toLowerCase();
        return str.includes(q);
      });

      const results = matched.slice(-maxResults);
      const summary = {
        ok: true,
        query,
        total_matches: matched.length,
        showing: results.length,
        entries: results,
      };
      return reply(summary);
    } catch (err) {
      return reply({ ok: false, error: `Ledger query failed: ${err.message}` });
    }
  }
);

// ── Tool: ledger_lifecycle ───────────────────────────────────────────────────
// Show the full lifecycle of a specific task: delegate → ack → report → verify → close.
server.tool(
  "ledger_lifecycle",
  "Show the full lifecycle of a task by ID. Returns every event: delegation, ACK, report, verification, close.",
  {
    task_id: z.string().describe("Task ID (e.g., 'sam-001', 'nel-005')"),
  },
  async ({ task_id }) => {
    try {
      const logPath = path.join(HYO_ROOT, "kai", "ledger", "log.jsonl");
      const raw = await readFile(logPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);
      const entries = lines.map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);

      const lifecycle = entries.filter(e => e.task_id === task_id);
      if (lifecycle.length === 0) {
        return reply({ ok: false, error: `No entries found for task_id: ${task_id}` });
      }

      const first = lifecycle[0];
      const last = lifecycle[lifecycle.length - 1];
      const status = last.status || last.action;
      const duration = first.ts && last.ts
        ? `${Math.round((new Date(last.ts) - new Date(first.ts)) / 1000)}s`
        : "unknown";

      return reply({
        ok: true,
        task_id,
        title: first.title || "—",
        status,
        steps: lifecycle.length,
        duration,
        events: lifecycle,
      });
    } catch (err) {
      return reply({ ok: false, error: `Lifecycle query failed: ${err.message}` });
    }
  }
);

// ─── Transport ───────────────────────────────────────────────────────────────
const cliArgs = process.argv.slice(2);
const transportArg = cliArgs.includes("--transport") ? cliArgs[cliArgs.indexOf("--transport") + 1] : "stdio";
const portArg = cliArgs.includes("--port") ? parseInt(cliArgs[cliArgs.indexOf("--port") + 1]) : 3847;

if (transportArg === "sse") {
  const httpServer = createServer(async (req, res) => {
    if (AUTH_TOKEN) {
      const token = req.headers["authorization"]?.replace("Bearer ", "");
      if (token !== AUTH_TOKEN) {
        res.writeHead(401, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "unauthorized" }));
        return;
      }
    }

    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, server: "hyo-mini-mcp", ts: mtnTimestamp() }));
      return;
    }

    const transport = new SSEServerTransport("/message", res);
    await server.connect(transport);
  });

  httpServer.listen(portArg, "0.0.0.0", () => {
    console.log(`hyo-mini-mcp listening on port ${portArg} (SSE transport)`);
    console.log(`Health check: http://localhost:${portArg}/health`);
    console.log(`HYO_ROOT: ${HYO_ROOT}`);
    console.log(`Tools: execute_command, git_push, deploy, read_file, write_file, kai, ledger_query, ledger_lifecycle`);
  });
} else {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("hyo-mini-mcp connected via stdio");
}
