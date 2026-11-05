//
//  ClaudeBridgeContract.swift
//  claude-notch
//
//  Contrato compartilhado. DEVE ser membro dos dois alvos de build.
//

import Foundation

/// Identificador do bundle do app. Se o fork for renomeado, muda só aqui.
public let claudeNotchBundleIdentifier = "theboringteam.boringnotch"

public enum ClaudeBridgeKind: String, Codable {
    case hook
    case statusline
}

/// Onde o Claude Code está rodando. Só a ponte sabe, porque roda dentro do
/// terminal; o app usa isto para levar o usuário de volta à aba certa.
public struct ClaudeTerminalInfo: Codable, Equatable {
    /// App que abriu o terminal (ex.: com.apple.Terminal), herdado do ambiente.
    public let bundleId: String?
    /// Nome do dispositivo do terminal, sem /dev/ (ex.: ttys003).
    public let tty: String?
    /// Dentro do tmux a tty é do tmux, não da aba; aí só dá para trazer o app.
    public let insideTmux: Bool
    /// Sessão hospedada pelo processo de fundo do Claude Code. Ela roda num
    /// terminal invisível e aparece numa aba qualquer que a esteja exibindo,
    /// então tty e app não servem: a aba é achada pelo título da conversa.
    public let background: Bool
    /// Título da conversa, o mesmo que o Claude Code escreve no título da aba.
    public let title: String?

    public init(bundleId: String?, tty: String?, insideTmux: Bool,
                background: Bool = false, title: String? = nil) {
        self.bundleId = bundleId
        self.tty = tty
        self.insideTmux = insideTmux
        self.background = background
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case bundleId, tty, insideTmux, background, title
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        tty = try c.decodeIfPresent(String.self, forKey: .tty)
        insideTmux = try c.decodeIfPresent(Bool.self, forKey: .insideTmux) ?? false
        background = try c.decodeIfPresent(Bool.self, forKey: .background) ?? false
        title = try c.decodeIfPresent(String.self, forKey: .title)
    }
}

/// O payload viaja como texto cru para não perder campos novos do Claude Code.
public struct ClaudeBridgeEnvelope: Codable {
    public var v: Int = 1
    public let kind: ClaudeBridgeKind
    public let sentAt: Int64
    public let payload: String
    /// Opcionais: ponte antiga não manda, e o envelope continua na versão 1.
    public let terminal: ClaudeTerminalInfo?
    /// Processo do Claude Code dono da sessão. Fechar a aba mata o processo
    /// sem o hook SessionEnd; é por ele que o app percebe que a sessão acabou.
    public let claudePid: Int32?

    public init(kind: ClaudeBridgeKind, sentAt: Int64, payload: String,
                terminal: ClaudeTerminalInfo? = nil, claudePid: Int32? = nil) {
        self.kind = kind
        self.sentAt = sentAt
        self.payload = payload
        self.terminal = terminal
        self.claudePid = claudePid
    }

    private enum CodingKeys: String, CodingKey {
        case v, kind, sentAt, payload, terminal, claudePid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Ausência de "v" significa versão 1: o envelope precisa sobreviver a
        // um remetente mais antigo, não recusá-lo.
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        kind = try c.decode(ClaudeBridgeKind.self, forKey: .kind)
        sentAt = try c.decode(Int64.self, forKey: .sentAt)
        payload = try c.decode(String.self, forKey: .payload)
        // Um campo de terminal estranho não pode custar o evento inteiro.
        terminal = try? c.decodeIfPresent(ClaudeTerminalInfo.self, forKey: .terminal)
        claudePid = try? c.decodeIfPresent(Int32.self, forKey: .claudePid)
    }
}

/// Todos opcionais de propósito: campo ausente não pode derrubar o app.
public struct ClaudeHookPayload: Decodable {
    public let hookEventName: String?
    public let sessionId: String?
    public let cwd: String?
    public let transcriptPath: String?
    public let permissionMode: String?
    public let toolName: String?
}

/// Campos que interessam da barra de status.
public struct ClaudeStatusLinePayload: Decodable {
    public struct Model: Decodable {
        public let id: String?
        public let displayName: String?
    }
    public struct Cost: Decodable {
        public let totalCostUsd: Double?
    }
    public struct ContextWindow: Decodable {
        public let usedPercentage: Double?
        public let contextWindowSize: Int?
    }
    public struct RateWindow: Decodable {
        public let usedPercentage: Double?
        public let resetsAt: Double?
    }
    public struct RateLimits: Decodable {
        public let fiveHour: RateWindow?
        public let sevenDay: RateWindow?
    }

    public let sessionId: String?
    public let cwd: String?
    public let transcriptPath: String?
    public let model: Model?
    public let cost: Cost?
    public let contextWindow: ContextWindow?
    public let rateLimits: RateLimits?
}

public enum ClaudeBridgeContract {
    /// O Claude Code emite JSON em snake_case; os tipos acima usam camelCase.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

public enum ClaudeBridgePaths {
    /// Curto de propósito: sun_path tem limite de 104 bytes.
    private static let socketFileName = "cn.sock"

    /// Dentro do sandbox, NSHomeDirectory() já aponta para <contêiner>/Data.
    /// Fora dela, aponta para a pasta pessoal real e o contêiner precisa ser montado.
    public static func socketPath(sandboxed: Bool) -> String {
        let home = NSHomeDirectory()
        if sandboxed {
            return home + "/tmp/" + socketFileName
        }
        return home
            + "/Library/Containers/" + claudeNotchBundleIdentifier
            + "/Data/tmp/" + socketFileName
    }
}
