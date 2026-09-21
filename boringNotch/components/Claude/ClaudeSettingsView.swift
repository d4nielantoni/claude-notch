//
//  ClaudeSettingsView.swift
//  boringNotch
//
//  Painel que liga e desliga a integração com o Claude Code.
//  É o único lugar do app que dispara escrita na configuração do usuário.
//

import Defaults
import SwiftUI

struct ClaudeSettings: View {
    @ObservedObject private var claude = ClaudeManager.shared

    @Default(.claudeIntegrationEnabled) private var enabled
    @Default(.claudeSettingsBookmark) private var settingsBookmark
    @Default(.claudeStaleAfterMinutes) private var staleAfter
    @Default(.claudeRemoveAfterMinutes) private var removeAfter
    @Default(.claudeLimitWarningThreshold) private var warningThreshold
    @Default(.claudeLimitCriticalThreshold) private var criticalThreshold

    /// Mesma regra do instalador: marca ligada E autorização presente.
    private var installed: Bool { enabled && settingsBookmark != nil }

    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Circle()
                        .fill(installed ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(installed ? "Installed" : "Not installed")
                    Spacer()
                    if installed {
                        Text("\(claude.sessions.count) live session(s)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if installed {
                    Button("Remove integration") {
                        run { try ClaudeIntegrationInstaller.shared.uninstall() }
                    }
                    .disabled(busy)
                } else {
                    Button("Install integration…") {
                        install()
                    }
                    .disabled(busy)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Integration")
            } footer: {
                Text("Adds a status line and event hooks to your Claude Code settings. "
                     + "Existing hooks are kept. A backup is written before any change, "
                     + "and removing the integration restores it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .showClaudeInClosedNotch) {
                    Text("Show indicator in the closed notch")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Slider(value: $warningThreshold, in: 50...95, step: 5) {
                    Text("Warning at \(Int(warningThreshold))%")
                }
                Slider(value: $criticalThreshold, in: 55...100, step: 5) {
                    Text("Critical at \(Int(criticalThreshold))%")
                }
            } header: {
                Text("Limit thresholds")
            }

            Section {
                Stepper("Dim a session after \(staleAfter) min of silence",
                        value: $staleAfter, in: 5...240, step: 5)
                Stepper("Drop a session after \(removeAfter) min of silence",
                        value: $removeAfter, in: 10...1440, step: 10)
            } header: {
                Text("Session cleanup")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Ações

    private func install() {
        busy = true
        errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            // O sandbox exige que o usuário aponte a pasta uma vez.
            guard await ClaudeIntegrationInstaller.shared.requestAccess() else {
                errorMessage = "Authorization cancelled."
                return
            }
            do {
                try ClaudeIntegrationInstaller.shared.install()
                ClaudeManager.shared.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func run(_ action: @escaping () throws -> Void) {
        busy = true
        errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try action()
                ClaudeManager.shared.stop()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
