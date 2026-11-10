# The agent door

A local API through which an agent on the same Mac (Claude, Codex, a script) looks at what mac4DSTEM's windows show, and
the MCP bridge that hands it to the agent as tools. Step one is read-only: the agent looks, the person drives.

## What an agent can do

| Tool (bridge) | Route (door) | Answer |
|---|---|---|
| `list_windows` | `GET /v1/windows` | the open windows: id, file, workspace and task, whether a run is in progress |
| `get_window` | `GET /v1/windows/<id>` | dataset and loaded view, calibration and its verdict, task and its settings, running operation, displayed result with provenance, disk-detection parameters and statistics, saved results, recipe steps |
| `get_result_image` | `GET /v1/windows/<id>/result.png` | the result figure File > Export writes: colour scale, scale bar, caption |
| `get_pattern_image` | `GET /v1/windows/<id>/pattern.png` | the diffraction pattern as its pane shows it; the detector outlined in the Virtual Detector task, the detected disks drawn in the Disks task |
| `get_detected_disks` | `GET /v1/windows/<id>/disks` | the detected disks of the pattern on screen |
| `get_lineage` | `GET /v1/windows/<id>/lineage` | the recipe and its run graph |
| `get_precipitate_objects` | `GET /v1/windows/<id>/objects` | the precipitate object table |
| `get_log` | `GET /v1/windows/<id>/log` | the Output lines |

`<id>` is `w1`, `w2`, ... or `current` while one window is open. Pictures take `?scale=1...3`. `GET /v1` lists the routes.
Every picture and number comes from the code that draws or exports it for the person, so the agent judges what the person sees.

## Turning it on

1. In mac4DSTEM: Settings > Agents > "Let agents on this Mac look at open windows". Off by default.
2. Build the bridge once: `swift build -c release --package-path AgentBridge` (the binary is `AgentBridge/.build/release/mac4dstem-mcp`).
3. Tell the agent about it, for Claude Code: `claude mcp add mac4dstem -- /path/to/mac4dstem-mcp`.

## How it is kept local

- The app listens on the loopback address (127.0.0.1) only, on a port the system picks, and only while the switch is on.
- When the door opens the app writes `Application Support/mac4DSTEM/agent-door.json` (inside the app's container), readable by
  the person's account only: the port and a token made new each time. The bridge reads it; a request without the token is refused.
- Requests from web pages (an `Origin` header) and requests whose `Host` is not the door's own are refused.
- The sandboxed app needs `com.apple.security.network.server` to listen at all. The app still sends nothing by itself.

The bridge finds the door through that file, or through `MAC4DSTEM_AGENT_DOOR` (the file's path), or
`MAC4DSTEM_AGENT_PORT` and `MAC4DSTEM_AGENT_TOKEN`.

## Code

`mac4DSTEM/App/AgentDoor/`: `AgentDoor` (the switch, the windows, the file), `AgentDoorServer` (the listener),
`AgentHTTP` (the request parser and `AgentDoorGate`), `AgentDoorRouter` (the routes), `AgentDoorSnapshot` (what a window says).
`AgentBridge/`: `Door` (finding and asking the door), `MCPServer` (the tools), `main` (stdio).

## Not yet

Running and tuning analyses (step two) and batches over several files (step three). Both go through the actions the
buttons use and are recorded in the lineage as run by an agent.
