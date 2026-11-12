# The agent door

A local API through which an agent on the same Mac (Claude, Codex, a script) looks at what mac4DSTEM's windows show. The app
is the MCP server itself, over HTTP at `http://127.0.0.1:47811/mcp`; nothing is installed beside it. This version is
read-only: the agent looks, the person drives.

The door itself (listener, token, Settings section, window list, MCP endpoint) is MacEMUI's `ShellAgentDoor` (MacEMUI
`docs/agent-door.md`), shared with macTEM. This app hands the door its tools.

## What an agent can do

| Tool | Answer |
|---|---|
| `list_windows` | the open windows: id, file, workspace and task, whether a run is in progress (the door's own tool) |
| `get_window` | dataset and loaded view, calibration and its verdict, task and its settings, running operation, displayed result with provenance, disk-detection parameters and statistics, saved results, recipe steps |
| `get_result_image` | the result figure File > Export writes: colour scale, scale bar, caption |
| `get_pattern_image` | the diffraction pattern as its pane shows it; the detector outlined in the Virtual Detector task, the detected disks drawn in the Disks task |
| `get_detected_disks` | the detected disks of the pattern on screen |
| `get_lineage` | the recipe and its run graph |
| `get_precipitate_objects` | the precipitate object table |
| `get_log` | the Output lines |

A window is `w1`, `w2`, ... (or none while one window is open). Pictures take `scale` 1...3; the pattern picture is drawn at
2 or more, as a Retina screen shows the pane, so the disk rings stand out as they do there (#185).
Every picture and number comes from the code that draws or exports it for the person, so the agent judges what the person sees.

## Turning it on

1. In mac4DSTEM: Settings > Agents > "Let agents on this Mac look at open windows". Off by default.
2. Press Copy Connection Command and paste it into Terminal once. It registers the app with Claude Code as an HTTP MCP
   server, with the port (mac4DSTEM asks for 47811) and the token. Cursor and VS Code take the same address and header.
   Claude desktop connects through MacEMUI's extension (`mac4DSTEM.mcpb`, MacEMUI `DesktopExtension/`).
3. New Token shuts out whoever had the old one; copy the command again after it.

## How it is kept local

- The app listens on the loopback address (127.0.0.1) only, and only while the switch is on.
- A request needs the token, kept in the app's preferences until New Token. Requests from web pages (an `Origin` header) and
  requests whose `Host` is not the door's own are refused.
- The sandboxed app needs `com.apple.security.network.server` to listen at all. The app still sends nothing by itself.

## Code

`mac4DSTEM/App/AgentDoor/`: `Mac4DSTEMAgentDoor` (the door and the tools), `AgentDoorSnapshot` (what a window says).
Settings > Agents is MacEMUI's `AgentDoorSettingsSection`.

## Not yet (5.3.0, issue #189)

Run and tune: tools that act, behind a second switch, "Let agents run analyses" (MacEMUI 0.7.0's `AgentTool(acts:)`).
They select a scan position, tune the disk detection, and press Run and Stop, through the actions the buttons use. Then the
folder tools for batches (list, open, save in one granted Agent folder), and the CIF-in orientation search as a tool.

## Task and Phase mapping (issue #209)

Behind "Let agents run analyses", like every tool that acts:

| Tool | What it does |
|---|---|
| `select_task` | moves the window to a task (`Disks`, `Phase mapping`, ...) or a workspace (`prepare`, `braggDisks`, `map`, ...), as the sidebar does; nothing runs |
| `set_phase_mapping` | Phase mapping's reference-library and matching fields, only the ones given; a new classifier resets the intensity floor, as the picker does |
| `scale_phase_matching_to_detector` | Scale to This Detector: the tolerances to one detector pixel; needs a physical Q pixel size |

`get_window`'s `view.task_settings` now carries Phase mapping's phases, settings, their size in detector pixels and why it
cannot run yet, and Diffraction groups' settings. The phases themselves are the person's until the CIF-in tool (#192).

## Calibration (issue #208)

Behind "Let agents run analyses", like every tool that acts:

| Tool | What it does |
|---|---|
| `set_calibration` | types the Q pixel size, the R pixel size (each with its unit) and the voltage, as Prepare's fields do; recorded as manual |
| `run_calibration` | starts Calibrate Origin, Origin from Bragg Peaks, Fit Ellipse (in the fit annulus given) or Measure R–Q Rotation |

Each answers with the calibration as `get_window` shows it, or says the step started. Clear Calibration stays with the person.
