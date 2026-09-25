// Minimal stdio MCP server exposing one shell tool with a tiny schema.
//
// This is the whole tool surface of the `sh` preset. It costs ~0 tokens in the
// context window, because the schema is three lines long.
//
// Runs on Node 18+ or Bun. No dependencies, no build step.
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const SHELL = process.env.CLAUDECUT_SHELL || "zsh";
// Where every command starts. Inherited from wherever claudecut was launched,
// which is the repository you are working in; nothing about any project is
// hardcoded. Passing it to the shell explicitly makes it a guarantee, and
// naming it in the tool description below is what lets the model stop writing
// `cd /long/absolute/path &&` in front of every command: the path is then paid
// once in the schema instead of once per call.
const CWD = process.env.CLAUDECUT_CWD || process.cwd();
const TIMEOUT_MS = Number(process.env.CLAUDECUT_SH_TIMEOUT_MS || 600000);
const MAX_OUTPUT = Number(process.env.CLAUDECUT_SH_MAX_OUTPUT || 60000);

// Two lines that run before every command, because measured sessions lose
// round trips to them: zsh aborts a command when an unquoted glob matches
// nothing (`grep --include=*.ts` -> "no matches found") and expands a leading
// `=` as a filename (`echo === x ===` -> "=== not found"); macOS ships no
// `timeout`, so a `timeout 120 cmd` is a command-not-found rather than a
// limit. The setopts are zsh-only and silently ignored elsewhere; the shim
// defines `timeout` only when the real one is absent, and alarm(2) gives it
// the same semantics rather than quietly dropping the limit.
//
// The color and pager variables are the same kind of saving, paid in context
// rather than round trips: one measured session carried 26k characters of ANSI
// escapes and box-drawing rules through every later request, which re-read them
// ~790k times in total. Nothing reads color out of a JSON-RPC pipe anyway.
const PRELUDE =
  process.env.CLAUDECUT_SH_PRELUDE ??
  'setopt NO_NOMATCH NO_EQUALS 2>/dev/null; ' +
  'export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 GIT_PAGER=cat PAGER=cat; ' +
  'command -v timeout >/dev/null 2>&1 || ' +
  'timeout() { perl -e \'alarm shift; exec @ARGV\' "$@"; }; ';

// Keep both ends of a long output. The head usually says what ran, the tail
// says how it went; dropping either silently is how a truncated result gets
// mistaken for the whole story.
const clip = (text) => {
  if (text.length <= MAX_OUTPUT) return text;
  const half = Math.floor(MAX_OUTPUT / 2);
  const dropped = text.length - half * 2;
  return (
    text.slice(0, half) +
    `\n\n[... ${dropped.toLocaleString("en-US")} characters truncated ...]\n\n` +
    text.slice(-half)
  );
};

const send = (msg) => process.stdout.write(JSON.stringify(msg) + "\n");

const tool = {
  name: "sh",
  description:
    `Run a shell command; returns stdout+stderr. Every call starts in ${CWD}, ` +
    "so no cd is needed. Each call is a separate round trip that re-reads the " +
    "whole context, so put independent steps in one call with && or ;.",
  inputSchema: {
    type: "object",
    properties: { cmd: { type: "string" } },
    required: ["cmd"],
  },
};

createInterface({ input: process.stdin }).on("line", (line) => {
  let req;
  try {
    req = JSON.parse(line);
  } catch {
    return; // Not our business; the transport will resend or fail loudly.
  }
  if (req.id === undefined) return; // Notification, no reply expected.

  const reply = (result) => send({ jsonrpc: "2.0", id: req.id, result });

  switch (req.method) {
    case "initialize":
      return reply({
        protocolVersion: req.params?.protocolVersion ?? "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "sh", version: "1" },
      });

    case "tools/list":
      return reply({ tools: [tool] });

    case "tools/call": {
      // Asynchronous on purpose. The first version used spawnSync, which
      // serialised the whole server: a `sleep 240` left every later call
      // queued behind it, and in one measured session six calls — including a
      // bare `echo ping` — sat for 120s until the client gave up on them and
      // moved them to the background. Nothing about running a command needs
      // the event loop held.
      const child = spawn(SHELL, ["-lc", PRELUDE + req.params.arguments.cmd], {
        cwd: CWD,
        stdio: ["ignore", "pipe", "pipe"],
      });

      let body = "";
      let killedByTimeout = false;
      let done = false;
      const take = (chunk) => {
        // Bound what is held in memory; clip() decides what is returned.
        if (body.length < MAX_OUTPUT * 8) body += chunk;
      };
      child.stdout.on("data", (c) => take(String(c)));
      child.stderr.on("data", (c) => take(String(c)));

      const timer = setTimeout(() => {
        killedByTimeout = true;
        child.kill("SIGKILL");
      }, TIMEOUT_MS);

      const finish = (status, signal, error) => {
        if (done) return; // 'error' and 'close' can both fire.
        done = true;
        clearTimeout(timer);
        const notes = [];
        if (killedByTimeout) notes.push(`[timed out after ${TIMEOUT_MS}ms]`);
        else if (error) notes.push(`[failed to run: ${error.message}]`);
        if (signal && !killedByTimeout) notes.push(`[killed by ${signal}]`);
        if (status) notes.push(`[exit ${status}]`);
        const text = clip(body) + (notes.length ? `\n${notes.join(" ")}` : "");
        reply({
          content: [{ type: "text", text: text || "(no output)" }],
          isError: Boolean(status) || Boolean(error) || killedByTimeout,
        });
      };

      child.on("error", (e) => finish(null, null, e));
      child.on("close", (status, signal) => finish(status, signal, null));
      return;
    }

    default:
      return send({
        jsonrpc: "2.0",
        id: req.id,
        error: { code: -32601, message: "method not found" },
      });
  }
});
