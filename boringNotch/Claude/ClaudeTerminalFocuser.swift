//
//  ClaudeTerminalFocuser.swift
//  boringNotch
//
//  Leva o usuário à janela onde uma sessão do Claude Code está rodando.
//  Nunca abre app nenhum: se o terminal já fechou, o clique não faz nada.
//

import AppKit

enum ClaudeTerminalFocuser {
    private static let appleTerminal = "com.apple.Terminal"
    private static let iTerm = "com.googlecode.iterm2"
    /// Só nestes dá para escolher a aba; também são onde procurar a aba que
    /// exibe uma sessão de fundo.
    private static let scriptableTerminals = [appleTerminal, iTerm]

    /// Como reconhecer a aba da sessão.
    private enum TabMatch {
        case tty(String)      // sessão comum: a aba é dona da tty
        case title(String)    // sessão de fundo: a aba exibe o título da conversa
    }

    /// Só promete o atalho (destaque e dica) se há onde chegar.
    static func canFocus(_ session: ClaudeSession) -> Bool {
        guard let terminal = session.terminal else { return false }
        if terminal.background {
            return terminal.title != nil && !runningScriptableTerminals().isEmpty
        }
        return runningApp(bundleId: terminal.bundleId) != nil
    }

    static func focus(_ session: ClaudeSession) {
        guard let terminal = session.terminal else { return }

        if terminal.background {
            // Não se sabe em que app está a aba que exibe a sessão: procura
            // em cada terminal aberto. Sem achar, não há para onde levar.
            guard let title = terminal.title else { return }
            let candidates = runningScriptableTerminals()
            Task {
                for bundleId in candidates {
                    if await runTabScript(bundleId: bundleId, match: .title(title)) { return }
                }
            }
            return
        }

        guard let bundleId = terminal.bundleId,
              let app = runningApp(bundleId: bundleId),
              let appURL = app.bundleURL
        else { return }

        Task {
            // Terminal e iTerm2 deixam escolher a aba pela tty. Nos outros
            // (ou dentro do tmux, ou se o usuário negou a permissão), trazer
            // o app para a frente é o melhor que dá.
            if !terminal.insideTmux, let tty = terminal.tty, isSafeTTYName(tty),
               await runTabScript(bundleId: bundleId, match: .tty(tty)) {
                return
            }
            await MainActor.run { bringToFront(appURL) }
        }
    }

    // MARK: Apps

    private static func runningApp(bundleId: String?) -> NSRunningApplication? {
        guard let bundleId else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private static func runningScriptableTerminals() -> [String] {
        scriptableTerminals.filter { runningApp(bundleId: $0) != nil }
    }

    /// O notch é um painel que nunca vira o app ativo, e o macOS 14+ pode
    /// ignorar um activate() pedido por quem não está na frente. Abrir o app
    /// pelo sistema (que já está rodando) é o caminho que ele respeita.
    private static func bringToFront(_ appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    // MARK: AppleScript

    /// true se achou e selecionou a aba.
    private static func runTabScript(bundleId: String, match: TabMatch) async -> Bool {
        guard let script = tabScript(bundleId: bundleId, match: match),
              let result = try? await AppleScriptHelper.execute(script)
        else { return false }
        return result.booleanValue
    }

    private static func tabScript(bundleId: String, match: TabMatch) -> String? {
        switch bundleId {
        case appleTerminal:
            let condition: String
            switch match {
            case .tty(let tty): condition = "tty of t is \"/dev/\(tty)\""
            case .title(let title): condition = "custom title of t contains \"\(escaped(title))\""
            }
            return """
            tell application id "\(appleTerminal)"
                repeat with w in windows
                    -- Janelas sem abas (Ajustes, Inspetor) dão erro em "tabs of".
                    try
                        repeat with t in tabs of w
                            if \(condition) then
                                if miniaturized of w then set miniaturized of w to false
                                set selected tab of w to t
                                set index of w to 1
                                activate
                                return true
                            end if
                        end repeat
                    end try
                end repeat
            end tell
            return false
            """
        case iTerm:
            let condition: String
            switch match {
            case .tty(let tty): condition = "tty of s is \"/dev/\(tty)\""
            case .title(let title): condition = "name of s contains \"\(escaped(title))\""
            }
            return """
            tell application id "\(iTerm)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if \(condition) then
                                try
                                    if miniaturized of w then set miniaturized of w to false
                                end try
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    /// A tty vai parar dentro do AppleScript; só aceitamos o formato de
    /// nome de dispositivo, nada que possa fechar a string.
    private static func isSafeTTYName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// O título vem da conversa e pode ter aspas; dentro da string do
    /// AppleScript só barra e aspas precisam de escape. Quebras de linha
    /// nunca aparecem no título da aba, então saem.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
