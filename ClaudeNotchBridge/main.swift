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

// Só os hooks trazem o caminho da conversa, de onde sai o título da sessão.
let transcriptPath = kind == .hook
    ? (try? ClaudeBridgeContract.decoder().decode(ClaudeHookPayload.self, from: input))?.transcriptPath
    : nil

// O Claude Code passa o próprio pid a tudo que dispara. Sem ele, nada de
// adivinhar pelo pai: pode ser um shell intermediário que morre em seguida,
// e o app tiraria do notch uma sessão viva.
let claudePid = ProcessInfo.processInfo.environment["CLAUDE_PID"].flatMap(Int32.init)

ClaudeBridgeClient.send(
    ClaudeBridgeEnvelope(
        kind: kind,
        sentAt: Int64(Date().timeIntervalSince1970 * 1000),
        payload: String(decoding: input, as: UTF8.self),
        terminal: ClaudeTerminalProbe.current(transcriptPath: transcriptPath, claudePid: claudePid),
        claudePid: claudePid
    )
)

// Em modo barra de status, o usuário precisa ver algo no terminal.
if kind == .statusline {
    print(ClaudeStatusLineFormatter.line(from: input))
}

exit(0)
