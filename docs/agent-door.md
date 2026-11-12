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
| `get_pattern_image` | the diffraction pattern as its pane shows it; the detector outlined in the Virtual Detector task, the detected disks drawn in the Disks task; `disks` false leaves them off, `crop_x`/`crop_y`/`crop_half` cut and magnify a square of detector pixels (#234) |
| `get_detected_disks` | the detected disks of the pattern on screen |
| `get_pattern_values` | the raw counts in a box around a detector pixel, its brightest pixel and the box edge's median (local background), to tell a weak disk from noise (#234) |
| `get_lineage` | the recipe and its run graph |
| `get_precipitate_objects` | the precipitate object table |
| `get_log` | the Output lines |

A window is `w1`, `w2`, ... (or none while one window is open). Pictures take `scale` 1...3; the pattern picture is drawn at
2 or more, as a Retina screen shows the pane, so the disk rings stand out as they do there (#185).
Every picture and number comes from the code that draws or exports it for the person, so the agent judges what the person sees.

### Tools that act

Behind a second switch, Settings > Agents > "Let agents run analyses", off by default. The agent's client asks the person
before each call (MCP marks them as not read-only). One run at a time; Stop in the window cancels it.

| Tool | Does |
|---|---|
| `select_scan_position` | shows the pattern at scan position x, y, as a click on the scan map does |
| `get_probe_kernel` | (looks) the probe radius and where it came from, the kernel built or null, the detector and threshold |
| `set_probe_radius` | the Probe radius field; a synthetic kernel already built is rebuilt at it |
| `build_probe_kernel` | Build Kernel: synthetic, from the pattern on screen, or the file's probe (the vacuum scan stays with the person) |
| `set_detector` | classical or neural net, and the neural net's threshold |
| `set_disk_detection` | sets the Disks fields it names (spacing, relative and absolute thresholds and their reference, smoothing of pattern and correlation, correlation power, edge, max peaks, subpixel `pixel`/`poly`/`multicorr` and its upsampling, #235); live detection follows (it says so when no probe kernel is built yet) |
| `run_task` | presses Run for the window's task |
| `stop_run` | presses Stop |

Every one of these writes an Output line that starts "An agent", so the person can tell the agent's values from their own.
When an action moves a setting the agent did not name, the Output says so: measuring the probe (Build Kernel, a probe radius,
Calibrate Origin) sets `min_peak_spacing` to fit the probe when nobody has chosen one, and writes "Build Kernel also changed
disk detection: min_peak_spacing 16 → 4". `get_probe_kernel` carries the disk settings too (#232). Numbers in the door's text use
a point, whatever the Mac's Region.

### The Agent folder (batches)

The person chooses one folder in Settings > Agents > Agent folder. Nothing outside it is listed, opened or written; paths
that lead out (`..`, links) are refused.

| Tool | Does |
|---|---|
| `list_agent_folder` | the files in the folder and its subfolders (looks only) |
| `open_file` | opens one in the window, as File > Open does (needs "Let agents run analyses") |
| `save_result_image` | saves the displayed result there as File > Export > Result Image does, with its provenance; needs "Let agents save results there" too, off by default; a name that exists is refused, so no file is ever replaced |

A batch is a loop: `list_agent_folder`, then for each file `open_file`, the run tools, `save_result_image`.

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

`mac4DSTEM/App/AgentDoor/`: `Mac4DSTEMAgentDoor` (the door and the tools that look), `AgentDoorSnapshot` (what a window says), `AgentDoorRuns` (the
tools that act), `AgentDoorFolder` and `AgentFolder` (the Agent folder).
Settings > Agents is MacEMUI's `AgentDoorSettingsSection`.

## Coverage

`mac4DSTEM/App/AgentDoor/AgentDoorCoverage.swift` lists every control in the UI, by its accessibility identifier, with how an
agent reaches it: the tool that does it, already seen in `get_window` or a picture, left to the person on purpose (with the
reason), or a gap with its open issue (#224 to #230, #192). `AgentDoorCoverageTests` fails when a control has no row, so a
new control cannot ship until someone decides. Today 34 controls have a tool, 95 are seen, 47 stay with the person and 90
are gaps.

## Not yet

The CIF-in orientation search as a tool (issue #192), once CIF in is in the app.

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
