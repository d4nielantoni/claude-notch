//
//  ClaudeStatusLineFormatter.swift
//  ClaudeNotchBridge
//

import Foundation

enum ClaudeStatusLineFormatter {
    /// Monta a linha que o usuário vê no terminal. Devolve string vazia se o
    /// JSON não puder ser lido — nunca falha.
    static func line(from data: Data) -> String {
        guard let p = try? ClaudeBridgeContract.decoder()
            .decode(ClaudeStatusLinePayload.self, from: data) else { return "" }

        var parts: [String] = []
        if let name = p.model?.displayName { parts.append(name) }
        if let cwd = p.cwd { parts.append((cwd as NSString).abbreviatingWithTildeInPath) }
        if let ctx = p.contextWindow?.usedPercentage { parts.append("ctx \(Int(ctx))%") }
        if let h = p.rateLimits?.fiveHour?.usedPercentage { parts.append("5h \(Int(h))%") }
        if let w = p.rateLimits?.sevenDay?.usedPercentage { parts.append("7d \(Int(w))%") }
        if let c = p.cost?.totalCostUsd { parts.append(String(format: "$%.2f", c)) }
        return parts.joined(separator: " · ")
    }
}
