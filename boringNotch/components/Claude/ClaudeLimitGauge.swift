//
//  ClaudeLimitGauge.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct ClaudeLimitGauge: View {
    let title: String
    let percentage: Double?
    let resetsAt: Date?

    private var value: Double { min(max(percentage ?? 0, 0), 100) }

    private var tint: Color {
        guard let p = percentage else { return .gray }
        if p >= Defaults[.claudeLimitCriticalThreshold] { return .red }
        if p >= Defaults[.claudeLimitWarningThreshold] { return .orange }
        return .green
    }

    private var resetText: String {
        guard let r = resetsAt else { return "—" }
        if r <= .now { return "resetting" }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return "resets in " + (f.string(from: .now, to: r) ?? "—")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text(percentage == nil ? "no data" : "\(Int(value))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * value / 100)
                        .animation(.smooth, value: value)
                }
            }
            .frame(height: 5)
            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.8))
        }
    }
}
