//
//  ClaudeLimitGauge.swift
//  boringNotch
//

import SwiftUI

struct ClaudeLimitGauge: View {
    let title: String
    let window: ClaudeLimitWindow?

    private static let resetFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        // Com dias: o limite de 7 dias virava "143h 20m".
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    private func resetText(now: Date) -> String {
        guard let r = window?.resetsAt else { return "—" }
        if r <= now { return "reset — waiting for new data" }
        return "resets in " + (Self.resetFormatter.string(from: now, to: r) ?? "—")
    }

    var body: some View {
        // Sem isto a contagem do reset só andava quando chegava um evento,
        // e o medidor ficava mostrando a janela velha depois de ela virar.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let value = window?.displayedPercentage(now: now)
            let tint = ClaudeLimitWindow.tint(for: value)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Spacer()
                    Text(value.map { "\(Int($0.rounded()))%" } ?? "no data")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(tint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * (value ?? 0) / 100)
                            .animation(.smooth, value: value)
                    }
                }
                .frame(height: 5)
                Text(resetText(now: now))
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.8))
            }
        }
    }
}
