//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

/// Só entra na barra a aba de um recurso que está ligado. Sem isto, a aba
/// "Claude" apareceria para quem nunca pediu a integração, e a "Shelf"
/// ressuscitaria para quem desligou a prateleira.
var tabs: [TabModel] {
    var lista = [TabModel(label: "Home", icon: "house.fill", view: .home)]
    if Defaults[.boringShelf] {
        lista.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
    }
    if Defaults[.claudeIntegrationEnabled] {
        lista.append(TabModel(label: "Claude", icon: TabButton.claudeMarkIcon, view: .claude))
    }
    return lista
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
