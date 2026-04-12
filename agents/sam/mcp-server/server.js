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
import { exec as execCb } from "child_process";
import { promisify } from "util";
import { readFile, writeFile, stat } from "fs/promises";
import { createServer } from "http";
import path from "path";

const exec = promisify(execCb);

// ─── Config ──────────────────────────────────────────────────────────────────
const HYO_ROOT = process.env.HYO_ROOT || path.join(process.env.HOME, "Documents", "Projects", "Hyo");
const AUTH_TOKEN = process.env.HYO_MCP_TOKEN || "";
const MAX_OUTPUT = 50_000;  // truncate stdout/stderr at 50KB
const COMMAND_TIMEOUT = 60_000;  // 60s timeout

// Commands that are NEVER allowed, regardless of context
const BLOCKED_PATTERNS = [
  /\brm\s+-rf\s+[/~]/,       // rm -rf on root-like paths
  /\bsudo\b/,                 // no sudo
  /\bmkfs\b/,                 // no formatting drives
  /\bdd\s+if=/,               // no raw disk writes
  /\b(shutdown|reboot|halt)\b/,
  /\blaunchctl\s+bootout\b/,  // no disabling system services
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

// ─── Server ──────────────────────────────────────────────────────────────────
const server = new McpServer({
  name: "hyo-mini",
  version: "1.0.0",
});

// ── Tool: execute_command ────────────────────────────────────────────────────
// Run any shell command on the Mini. Returns stdout, stderr, exit code.
server.tool(
  "execute_command",
  "Run a shell command on the Mac Mini. Returns stdout, stderr, and exit code.",
  {
    command: { type: "string", description: "Shell command to execute" },
    cwd: { type: "string", description: "Working directory (default: HYO_ROOT)", default: "" },
    timeout: { type: "number", description: "Timeout in ms (default: 60000)", default: 60000 },
  },
  async ({ command, cwd, timeout }) => {
    if (isBlocked(command)) {
      return { content: [{ type: "text", text: `BLOCKED: command matched safety filter.\nCommand: ${command}` }] };
    }
    const dir = cwd || HYO_ROOT;
    const to = Math.min(timeout || COMMAND_TIMEOUT, 120_000);
    try {
      const { stdout, stderr } = await exec(command, {
        cwd: dir,
        timeout: to,
        maxBuffer: 5 * 1024 * 1024,
        env: { ...process.env, HYO_ROOT },
      });
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            ok: true,
            exit_code: 0,
            stdout: truncate(stdout),
            stderr: truncate(stderr),
            cwd: dir,
            ts: mtnTimestamp(),
          }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            ok: false,
            exit_code: err.code || 1,
            stdout: truncate(err.stdout),
            stderr: truncate(err.stderr || err.message),
            cwd: dir,
            ts: mtnTimestamp(),
          }, null, 2),
        }],
      };
    }
  }
);

// ── Tool: git_push ───────────────────────────────────────────────────────────
// Dedicated git push tool with safety checks.
server.tool(
  "git_push",
  "Push the Hyo repo to origin. Runs pre-deploy validation first.",
  {
    branch: { type: "string", description: "Branch to push (default: main)", default: "main" },
    force: { type: "boolean", description: "Force push (default: false)", default: false },
  },
  async ({ branch, force }) => {
    const br = branch || "main";
    if (force && br === "main") {
      return { content: [{ type: "text", text: "BLOCKED: force push to main is not allowed." }] };
    }
    try {
      // Run pre-deploy validation first
      const validate = await exec(`python3 bin/predeploy-validate.py`, { cwd: HYO_ROOT, timeout: 30_000, env: { ...process.env, HYO_ROOT } });
      if (validate.stderr && validate.stderr.includes("deploy blocked")) {
        return {
          content: [{ type: "text", text: `Pre-deploy validation FAILED:\n${validate.stdout}\n${validate.stderr}` }],
        };
      }

      const cmd = force ? `git push --force origin ${br}` : `git push origin ${br}`;
      const { stdout, stderr } = await exec(cmd, { cwd: HYO_ROOT, timeout: 60_000 });
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            ok: true,
            action: `git push origin ${br}`,
            stdout: truncate(stdout),
            stderr: truncate(stderr),
            ts: mtnTimestamp(),
          }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            ok: false,
            action: `git push origin ${br}`,
            error: err.message,
            stdout: truncate(err.stdout),
            stderr: truncate(err.stderr),
            ts: mtnTimestamp(),
          }, null, 2),
        }],
      };
    }
  }
);

// ── Tool: deploy ─────────────────────────────────────────────────────────────
// Full deploy pipeline: validate → git push → verify.
server.tool(
  "deploy",
  "Full deploy pipeline: pre-deploy validation → git push → wait → health check.",
  {
    message: { type: "string", description: "What triggered this deploy", default: "manual" },
  },
  async ({ message }) => {
    const steps = [];
    try {
      // Step 1: validate
      const v = await exec(`python3 bin/predeploy-validate.py`, { cwd: HYO_ROOT, timeout: 30_000, env: { ...process.env, HYO_ROOT } });
      steps.push({ step: "validate", ok: true, output: truncate(v.stdout) });

      // Step 2: git push
      const p = await exec(`git push origin main`, { cwd: HYO_ROOT, timeout: 60_000 });
      steps.push({ step: "git_push", ok: true, output: truncate(p.stderr || p.stdout) });

      // Step 3: wait for Vercel
      await new Promise(r => setTimeout(r, 10_000));

      // Step 4: health check
      const h = await exec(`curl -sf https://www.hyo.world/api/health`, { timeout: 15_000 });
      steps.push({ step: "health_check", ok: true, output: truncate(h.stdout) });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({ ok: true, message, steps, ts: mtnTimestamp() }, null, 2),
        }],
      };
    } catch (err) {
      steps.push({ step: "failed", ok: false, error: err.message });
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ ok: false, message, steps, ts: mtnTimestamp() }, null, 2),
        }],
      };
    }
  }
);

// ── Tool: read_file ──────────────────────────────────────────────────────────
server.tool(
  "read_file",
  "Read a file from the Hyo project directory.",
  {
    path: { type: "string", description: "Relative path from HYO_ROOT (e.g., 'KAI_BRIEF.md')" },
  },
  async ({ path: filePath }) => {
    try {
      const full = path.resolve(HYO_ROOT, filePath);
      if (!full.startsWith(HYO_ROOT)) {
        return { content: [{ type: "text", text: "BLOCKED: path escapes project directory." }] };
      }
      const content = await readFile(full, "utf-8");
      return { content: [{ type: "text", text: truncate(content) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error reading file: ${err.message}` }] };
    }
  }
);

// ── Tool: write_file ─────────────────────────────────────────────────────────
server.tool(
  "write_file",
  "Write content to a file in the Hyo project directory.",
  {
    path: { type: "string", description: "Relative path from HYO_ROOT" },
    content: { type: "string", description: "File content to write" },
  },
  async ({ path: filePath, content }) => {
    try {
      const full = path.resolve(HYO_ROOT, filePath);
      if (!full.startsWith(HYO_ROOT)) {
        return { content: [{ type: "text", text: "BLOCKED: path escapes project directory." }] };
      }
      await writeFile(full, content, "utf-8");
      const s = await stat(full);
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ ok: true, path: filePath, bytes: s.size, ts: mtnTimestamp() }, null, 2),
        }],
      };
    } catch (err) {
      return { content: [{ type: "text", text: `Error writing file: ${err.message}` }] };
    }
  }
);

// ── Tool: kai ────────────────────────────────────────────────────────────────
// Run any kai.sh subcommand directly.
server.tool(
  "kai",
  "Run a kai.sh subcommand (e.g., 'health', 'verify', 'validate', 'gitpush').",
  {
    subcommand: { type: "string", description: "Kai subcommand (e.g., 'health', 'verify', 'deploy')" },
    args: { type: "string", description: "Additional arguments", default: "" },
  },
  async ({ subcommand, args }) => {
    const cmd = `bash bin/kai.sh ${subcommand} ${args || ""}`.trim();
    try {
      const { stdout, stderr } = await exec(cmd, { cwd: HYO_ROOT, timeout: 120_000, env: { ...process.env, HYO_ROOT } });
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ ok: true, command: `kai ${subcommand}`, stdout: truncate(stdout), stderr: truncate(stderr), ts: mtnTimestamp() }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ ok: false, command: `kai ${subcommand}`, error: err.message, stdout: truncate(err.stdout), stderr: truncate(err.stderr), ts: mtnTimestamp() }, null, 2),
        }],
      };
    }
  }
);

// ─── Transport ───────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const transportArg = args.includes("--transport") ? args[args.indexOf("--transport") + 1] : "stdio";
const portArg = args.includes("--port") ? parseInt(args[args.indexOf("--port") + 1]) : 3847;

if (transportArg === "sse") {
  // SSE transport for remote Cowork connector
  const httpServer = createServer(async (req, res) => {
    // Optional auth check
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

    // Let the SSE transport handle MCP protocol
    const transport = new SSEServerTransport("/message", res);
    await server.connect(transport);
  });

  httpServer.listen(portArg, "0.0.0.0", () => {
    console.log(`hyo-mini-mcp listening on port ${portArg} (SSE transport)`);
    console.log(`Health check: http://localhost:${portArg}/health`);
    console.log(`HYO_ROOT: ${HYO_ROOT}`);
  });
} else {
  // Stdio transport for local Claude Code
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("hyo-mini-mcp connected via stdio");
}
