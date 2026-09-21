//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    /// Nome reservado: em vez de um símbolo do sistema, desenha a marca do
    /// Claude. Evita mudar a assinatura do botão e todos os pontos de chamada.
    static let claudeMarkIcon = "__claude_mark__"

    var body: some View {
        Button(action: onClick) {
            Group {
                if icon == Self.claudeMarkIcon {
                    ClaudeMark(size: 15)
                } else {
                    Image(systemName: icon)
                }
            }
            .padding(.horizontal, 15)
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
