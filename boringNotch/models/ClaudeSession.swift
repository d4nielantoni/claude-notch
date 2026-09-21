//
//  ClaudeSession.swift
//  boringNotch
//

import Foundation
import SwiftUI

enum ClaudeSessionState: String {
    case idle
    case working
    case waiting
    case compacting
    case error

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Waiting for you"
        case .compacting: return "Compacting"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .working: return .green
        case .waiting: return .orange
        case .compacting: return .blue
        case .error: return .red
        }
    }

    /// Estados que merecem roubar o notch fechado da animação de rosto.
    var demandsAttention: Bool {
        self == .working || self == .waiting || self == .error
    }
}

struct ClaudeSession: Identifiable, Equatable {
    let id: String              // session_id
    var projectPath: String?    // cwd
    var state: ClaudeSessionState = .idle
    var currentTool: String?
    var subagentCount: Int = 0
    var modelName: String?
    var contextPercentage: Double?
    var costUSD: Double?
    var lastEventAt: Date = .now

    /// Só o último componente do caminho — é o que cabe no notch.
    var projectName: String {
        guard let p = projectPath, !p.isEmpty else { return "session" }
        return (p as NSString).lastPathComponent
    }

    func isStale(now: Date, staleAfterMinutes: Int) -> Bool {
        now.timeIntervalSince(lastEventAt) > Double(staleAfterMinutes) * 60
    }
}

struct ClaudeAccountLimits: Equatable {
    var fiveHourPercentage: Double?
    var fiveHourResetsAt: Date?
    var sevenDayPercentage: Double?
    var sevenDayResetsAt: Date?
    /// Instante do envelope que produziu estes números, em milissegundos.
    var sourceSentAt: Int64 = 0

    var isEmpty: Bool { fiveHourPercentage == nil && sevenDayPercentage == nil }
}
