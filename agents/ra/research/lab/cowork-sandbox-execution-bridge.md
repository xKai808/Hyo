# Cowork Sandbox → Mini Execution Bridge

**Date:** 2026-04-12  
**Category:** Infrastructure / DevOps  
**Status:** Researched — ready for implementation  
**Priority:** P0 (blocks autonomous deployment)

---

## Problem

Claude Cowork runs in a sandboxed Linux environment with blocked outbound HTTPS. Git push, npm deploy, curl to external domains — all return 403 from the egress proxy. The Mac Mini has full network access but Cowork can't execute commands on it. Current workaround: Hyo manually copy/pastes terminal commands. This is the #1 bottleneck.

## Viable Solutions (Ranked)

### 1. Custom Remote MCP Server (RECOMMENDED)

Build an HTTPS server on the Mini that implements MCP protocol. Cowork calls tools like `execute_command`, `git_push`, `deploy`. The server runs commands on the Mini and returns results.

**Architecture:** Mini runs Node.js MCP server → exposed via Tailscale/Cloudflare Tunnel → Cowork connects as custom connector in Settings → Connectors.

**Setup:** 3-4 hours. Use `npm init @modelcontextprotocol/mcp-server-template`. Define tools wrapping `child_process.exec()`. Deploy as launchd agent. Expose via tunnel. Add to Cowork as custom connector.

**Security:** OAuth/token auth, command allowlisting, execution logging. Never expose Mini's real IP.

**Solves:** Git push, npm deploy, Vercel deploy, arbitrary script execution. Full network access from Mini.

### 2. File-Watcher Dispatch Loop (BACKUP)

Cowork writes JSON command files to FUSE mount. launchd + fswatch on Mini watches directory, executes commands, writes response files. Cowork polls for responses.

**Risk:** FUSE mount has documented cache coherency bugs (GitHub issue #42520). Response files may be corrupted or invisible to Cowork. Medium reliability.

**Setup:** 4-5 hours including FUSE debugging.

### 3. GitHub Actions Intermediary (CONDITIONAL)

Cowork triggers GitHub Actions via REST API (`repository_dispatch`). Actions run with full network access. Requires `api.github.com` to be allowlisted in sandbox egress.

**Blocker:** Must verify GitHub API reachability from Cowork first. 1-2 minute latency per dispatch.

### Not Viable

- **SSH tunnel:** Sandbox blocks TCP ports, not just HTTPS
- **Claude Code hooks:** Only fire locally, can't bridge Cowork → Mini
- **Plugins alone:** Organizational tool, not execution bridge

## Implementation Plan

**Week 1:**
1. Build MCP server with tools: `execute_command`, `git_push`, `deploy`
2. Install Tailscale on Mini (`brew install tailscale && tailscale up`)
3. Expose MCP server via Tailscale hostname
4. Add custom connector in Cowork settings
5. Test end-to-end: Cowork invokes tool → Mini executes → result returns

**Security checklist:**
- [ ] Token-based auth on MCP server
- [ ] Command allowlist (git, npm, vercel, kai — no rm -rf, sudo)
- [ ] Execution logging to file
- [ ] Rate limiting (reject if queue > 10)

## Sources

- [Build MCP Server](https://modelcontextprotocol.io/docs/develop/build-server)
- [Custom Connectors via Remote MCP](https://support.claude.com/en/articles/11503834)
- [Cowork Sandboxing Docs](https://code.claude.com/docs/en/sandboxing)
- [FUSE Cache Bug #42520](https://github.com/anthropics/claude-code/issues/42520)
