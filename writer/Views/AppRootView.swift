import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.lockState {
            case .locked:
                UnlockView()
            case .unlocked:
                EditorView()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
