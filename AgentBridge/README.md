# mac4dstem-mcp

The MCP bridge to mac4DSTEM's agent door: it lets an agent (Claude, Codex) look at what the app's windows show. It is a small
tool of its own, not part of the app. What the door answers and how it is kept local: `docs/agent-door.md`.

```sh
swift build -c release --package-path AgentBridge
claude mcp add mac4dstem -- "$PWD/AgentBridge/.build/release/mac4dstem-mcp"
```

In mac4DSTEM, turn the door on first: Settings > Agents. The bridge only looks; it changes nothing in the app.

`swift test --package-path AgentBridge` runs its tests (no app and no port needed).
