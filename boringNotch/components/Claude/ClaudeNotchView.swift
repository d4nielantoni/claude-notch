//
//  ClaudeNotchView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct ClaudeNotchView: View {
    @ObservedObject var claude = ClaudeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                ClaudeLimitGauge(
                    title: "5-hour limit",
                    percentage: claude.limits.fiveHourPercentage,
                    resetsAt: claude.limits.fiveHourResetsAt
                )
                ClaudeLimitGauge(
                    title: "7-day limit",
                    percentage: claude.limits.sevenDayPercentage,
                    resetsAt: claude.limits.sevenDayResetsAt
                )
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 2) {
                if claude.sessions.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "moon.zzz")
                            .foregroundStyle(.gray)
                        Text(Defaults[.claudeIntegrationEnabled]
                             ? "No active sessions"
                             : "Integration disabled")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(claude.sessions) { ClaudeSessionRow(session: $0) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}
