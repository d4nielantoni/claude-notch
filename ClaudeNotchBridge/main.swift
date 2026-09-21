//
//  main.swift
//  ClaudeNotchBridge
//
//  Invocado pelo Claude Code de dois jeitos:
//    claude-notch-bridge hook
//    claude-notch-bridge statusline
//

import Foundation

let mode = CommandLine.arguments.dropFirst().first ?? "hook"
let kind: ClaudeBridgeKind = (mode == "statusline") ? .statusline : .hook

let input = FileHandle.standardInput.readDataToEndOfFile()

ClaudeBridgeClient.send(
    ClaudeBridgeEnvelope(
        kind: kind,
        sentAt: Int64(Date().timeIntervalSince1970 * 1000),
        payload: String(data: input, encoding: .utf8) ?? ""
    )
)

// Em modo barra de status, o usuário precisa ver algo no terminal.
if kind == .statusline {
    print(ClaudeStatusLineFormatter.line(from: input))
}

exit(0)
