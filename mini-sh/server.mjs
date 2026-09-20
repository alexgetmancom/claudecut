// Minimal stdio MCP server exposing one shell tool with a tiny schema.
//
// This is the whole tool surface of the `sh` preset. It costs ~0 tokens in the
// context window, because the schema is three lines long.
//
// Runs on Node 18+ or Bun. No dependencies, no build step.
import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline";

const SHELL = process.env.CLAUDECUT_SHELL || "zsh";
const TIMEOUT_MS = Number(process.env.CLAUDECUT_SH_TIMEOUT_MS || 600000);
const MAX_OUTPUT = Number(process.env.CLAUDECUT_SH_MAX_OUTPUT || 60000);

const send = (msg) => process.stdout.write(JSON.stringify(msg) + "\n");

const tool = {
  name: "sh",
  description: "Run a shell command in the project directory. Returns stdout+stderr.",
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
      // A login shell, so PATH and tooling match the user's own terminal.
      const r = spawnSync(SHELL, ["-lc", req.params.arguments.cmd], {
        encoding: "utf8",
        timeout: TIMEOUT_MS,
        maxBuffer: 1 << 26,
      });
      const body = `${r.stdout ?? ""}${r.stderr ?? ""}`;
      const text = body + (r.status ? `\n[exit ${r.status}]` : "");
      return reply({
        content: [{ type: "text", text: text.slice(-MAX_OUTPUT) || "(no output)" }],
        isError: r.status !== 0,
      });
    }

    default:
      return send({
        jsonrpc: "2.0",
        id: req.id,
        error: { code: -32601, message: "method not found" },
      });
  }
});
