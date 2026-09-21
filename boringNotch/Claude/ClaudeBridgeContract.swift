//
//  ClaudeBridgeContract.swift
//  claude-notch
//
//  Contrato compartilhado entre o app e o executável da ponte.
//  Este arquivo DEVE ser membro dos dois alvos.
//

import Foundation

/// Identificador do bundle do app. Se o fork for renomeado, muda só aqui.
public let claudeNotchBundleIdentifier = "theboringteam.boringnotch"

public enum ClaudeBridgeKind: String, Codable {
    case hook
    case statusline
}

/// Envelope versionado. O payload viaja como texto cru para que nenhum campo
/// novo do Claude Code se perca antes de chegar no app.
public struct ClaudeBridgeEnvelope: Codable {
    public var v: Int = 1
    public let kind: ClaudeBridgeKind
    public let sentAt: Int64
    public let payload: String

    public init(kind: ClaudeBridgeKind, sentAt: Int64, payload: String) {
        self.kind = kind
        self.sentAt = sentAt
        self.payload = payload
    }
}

/// Campos que interessam de um gancho. Todos opcionais de propósito:
/// o Claude Code evolui, e um campo ausente não pode derrubar o app.
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
    /// Nome curto de propósito: o caminho completo precisa caber em 104 bytes,
    /// que é o limite do sistema para soquetes de domínio Unix.
    private static let socketFileName = "cn.sock"

    /// Dentro da caixa de areia, NSHomeDirectory() já aponta para <contêiner>/Data.
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
