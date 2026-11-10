// SPDX-License-Identifier: GPL-3.0-only
//
//  mac4dstem-mcp: the MCP bridge to mac4DSTEM's agent door, over stdio. An MCP client (Claude, Codex) starts it and writes one
//  JSON-RPC message per line on its standard input; each answer is one line on standard output. It ends when the input ends.
//
//      claude mcp add mac4dstem -- /path/to/mac4dstem-mcp
//
//  Standard output carries protocol messages only; anything for a person goes to standard error.
//

import AgentBridgeCore
import Foundation

if CommandLine.arguments.contains("--version") {
    print("mac4dstem-mcp \(MCPServer.serverVersion)")
    exit(0)
}
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
        mac4dstem-mcp \(MCPServer.serverVersion): the MCP bridge to mac4DSTEM's agent door.

        Started by an MCP client, which talks to it over standard input and output:
            claude mcp add mac4dstem -- \(CommandLine.arguments[0])

        In mac4DSTEM, turn the door on first: Settings > Agents > "Let agents on this Mac look at open windows".
        The bridge looks; it changes nothing in the app.
        """)
    exit(0)
}

let server = MCPServer(door: LocalDoor())
let output = FileHandle.standardOutput
while let line = readLine(strippingNewline: true) {
    guard let answer = server.handle(line: line) else { continue }
    output.write(Data((answer + "\n").utf8))
}
