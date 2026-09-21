//
//  ClaudeLiveActivity.swift
//  boringNotch
//
//  O que aparece no notch fechado: um ponto que pulsa quando o Claude trabalha
//  e um anel fino que enche conforme o limite de 5 horas queima.
//

import Defaults
import SwiftUI

struct ClaudeLiveActivity: View {
    @ObservedObject var claude = ClaudeManager.shared

    private var session: ClaudeSession? { claude.highlighted }

    private var ringValue: Double {
        min(max(claude.limits.fiveHourPercentage ?? 0, 0), 100) / 100
    }

    private var ringTint: Color {
        guard let p = claude.limits.fiveHourPercentage else { return .gray }
        if p >= Defaults[.claudeLimitCriticalThreshold] { return .red }
        if p >= Defaults[.claudeLimitWarningThreshold] { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: ringValue)
                    .stroke(ringTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: ringValue)
                Image(systemName: "sparkles")
                    .font(.system(size: 7))
                    .foregroundStyle(session?.state.color ?? .gray)
            }
            .frame(width: 18, height: 18)
            .opacity(session?.state == .working ? 0.55 : 1)
            .animation(
                session?.state == .working
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: session?.state
            )

            if let s = session {
                Text(s.projectName)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }
}
