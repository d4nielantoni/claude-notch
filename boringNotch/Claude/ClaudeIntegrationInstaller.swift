//
//  ClaudeIntegrationInstaller.swift
//  boringNotch
//
//  Escreve e remove as entradas do claude-notch em ~/.claude/settings.json.
//  Some por cima do que já existe: o que o usuário configurou sobrevive.
//

import AppKit
import Defaults
import Foundation

enum ClaudeInstallError: LocalizedError {
    case noAccess
    case unreadableSettings
    case malformedSettings
    case statusLineTaken(String)
    case bridgeMissing
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAccess:
            return "Point me at your Claude settings folder once, so I can install the hooks."
        case .unreadableSettings:
            return "Could not read settings.json."
        case .malformedSettings:
            return "settings.json is not valid JSON. Refusing to write to it."
        case .statusLineTaken(let cmd):
            return "You already have a status line configured (\(cmd)). Refusing to overwrite it."
        case .bridgeMissing:
            return "Could not find the bridge inside the app bundle."
        case .backupFailed(let reason):
            return "Could not write a backup of settings.json (\(reason)). Refusing to modify it."
        }
    }
}

final class ClaudeIntegrationInstaller {
    static let shared = ClaudeIntegrationInstaller()
    private init() {}

    /// Os treze eventos que alimentam a máquina de estados.
    private let hookEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "Stop", "StopFailure",
        "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification",
        "PreCompact", "PostCompact", "SubagentStart", "SubagentStop"
    ]
    private let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure"]

    private var bridgePath: String? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/claude-notch-bridge")
            .path
    }

    var isInstalled: Bool { Defaults[.claudeIntegrationEnabled] }

    // MARK: Autorização

    /// Abre o seletor já na pasta certa. A caixa de areia exige que o usuário
    /// aponte a PASTA; depois disso o marcador persiste e isso não se repete.
    ///
    /// É a pasta, e não o arquivo, porque escrever settings.json com segurança
    /// exige dois vizinhos dele: o backup e o temporário da escrita atômica.
    /// Com autorização só do arquivo, a caixa de areia bloquearia os dois.
    @MainActor
    func requestAccess() async -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Choose your .claude folder (the one holding settings.json)"
        panel.prompt = "Authorize"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return false }

        Defaults[.claudeSettingsBookmark] = bookmark
        return true
    }

    /// Devolve a PASTA autorizada. O acesso protegido é aberto sobre ela,
    /// e o settings.json é alcançado como filho.
    private func claudeDirectory() throws -> URL {
        guard let data = Defaults[.claudeSettingsBookmark] else { throw ClaudeInstallError.noAccess }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { throw ClaudeInstallError.noAccess }

        // Marcador obsoleto (pasta movida ou renomeada): regrava agora. Sem isto
        // ele degrada em silêncio até exigir reautorização sem explicação.
        if stale {
            url.accessSecurityScopedResource { scoped in
                if let novo = try? scoped.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    Defaults[.claudeSettingsBookmark] = novo
                }
            }
        }

        return url
    }

    // MARK: Instalar

    func install() throws {
        guard let bridge = bridgePath,
              FileManager.default.fileExists(atPath: bridge) else {
            throw ClaudeInstallError.bridgeMissing
        }

        let dir = try claudeDirectory()
        try dir.accessSecurityScopedResource { dir in
            let url = dir.appendingPathComponent("settings.json")
            var json = try loadSettings(url)

            // Barra de status: nunca sobrescreve a do usuário.
            // Qualquer statusLine que não seja reconhecidamente nossa é do usuário
            // e não se toca — inclusive uma malformada, que antes escapava.
            if let existing = json["statusLine"] {
                let cmd = (existing as? [String: Any])?["command"] as? String
                if cmd?.contains("claude-notch-bridge") != true {
                    throw ClaudeInstallError.statusLineTaken(cmd ?? "unrecognized configuration")
                }
            }
            json["statusLine"] = [
                "type": "command",
                "command": "\"\(bridge)\" statusline",
                "refreshInterval": 30
            ]

            // Ganchos: soma, nunca substitui.
            var hooks = json["hooks"] as? [String: Any] ?? [:]
            for event in hookEvents {
                var entries = hooks[event] as? [[String: Any]] ?? []
                entries.removeAll { entryPointsAtUs($0) }
                var entry: [String: Any] = [
                    "hooks": [["type": "command", "command": "\"\(bridge)\" hook"]]
                ]
                if toolEvents.contains(event) { entry["matcher"] = "*" }
                entries.append(entry)
                hooks[event] = entries
            }
            json["hooks"] = hooks

            try writeSettings(json, to: url)
        }

        Defaults[.claudeIntegrationEnabled] = true
    }

    // MARK: Desinstalar

    func uninstall() throws {
        let dir = try claudeDirectory()
        try dir.accessSecurityScopedResource { dir in
            let url = dir.appendingPathComponent("settings.json")
            var json = try loadSettings(url)

            if let sl = json["statusLine"] as? [String: Any],
               let cmd = sl["command"] as? String,
               cmd.contains("claude-notch-bridge") {
                json.removeValue(forKey: "statusLine")
            }

            if var hooks = json["hooks"] as? [String: Any] {
                for event in hookEvents {
                    guard var entries = hooks[event] as? [[String: Any]] else { continue }
                    entries.removeAll { entryPointsAtUs($0) }
                    if entries.isEmpty { hooks.removeValue(forKey: event) }
                    else { hooks[event] = entries }
                }
                if hooks.isEmpty { json.removeValue(forKey: "hooks") }
                else { json["hooks"] = hooks }
            }

            try writeSettings(json, to: url)
        }

        Defaults[.claudeIntegrationEnabled] = false
    }

    /// Reconhece uma entrada nossa pelo comando. Assim o `rtk hook claude`
    /// e qualquer outro gancho do usuário passam ilesos.
    private func entryPointsAtUs(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains("claude-notch-bridge") == true }
    }

    // MARK: Leitura e escrita

    private func loadSettings(_ url: URL) throws -> [String: Any] {
        // Arquivo ausente é primeira instalação legítima, não erro: seguimos com
        // configuração vazia e o arquivo nasce na escrita.
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else {
            throw ClaudeInstallError.unreadableSettings
        }
        if data.isEmpty { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeInstallError.malformedSettings
        }
        return json
    }

    private func backupURL(besides url: URL) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS"
        return url.deletingLastPathComponent()
            .appendingPathComponent("settings.json.claude-notch-backup-\(f.string(from: Date()))")
    }

    /// Backup ANTES de escrever, e com falha visível: sem rede de segurança
    /// confirmada, não mexemos no arquivo de que o usuário depende para trabalhar.
    private func writeSettings(_ json: [String: Any], to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let current = try Data(contentsOf: url)
                try current.write(to: backupURL(besides: url))
            } catch {
                throw ClaudeInstallError.backupFailed(error.localizedDescription)
            }
        }
        let out = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try out.write(to: url, options: .atomic)
    }
}
