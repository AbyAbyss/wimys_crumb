// WimysCrumbApp.swift
// App entry, WindowGroup, native title bar, content layout.

import SwiftUI

@main
struct WimysCrumbApp: App {
    @State private var app = AppModel()

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .frame(minWidth: 1100, minHeight: 740)
                .background(Color.cBg)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
    }
}

/// Application root: BrandBar + active screen + overlays (toast + delete sheet).
struct RootView: View {
    @Bindable var app: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrandBar(app: app)
                screenContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Subtle fade + tiny upward translate on screen change (plan §6.1).
                    .id(app.screen)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        )
                    )
            }
            .animation(.easeOut(duration: 0.25), value: app.screen)

            // Delete confirmation sheet — overlay on top of the screen,
            // under the toast. Sits inside the ZStack so backdrop taps
            // dismiss without leaving the window.
            if app.deleteSheetOpen {
                DeleteSheet(app: app)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeOut(duration: 0.18), value: app.deleteSheetOpen)
            }

            if let t = app.toast {
                ToastView(toast: t, onActionTap: {
                    if t.action?.kind == .undoDelete {
                        app.runPendingUndo()
                    }
                    app.dismissToast()
                })
                    .padding(.bottom, 22)
                    .task(id: t.id) {
                        // Auto-dismiss.
                        let nanos = UInt64(t.duration * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: nanos)
                        if app.toast?.id == t.id { app.dismissToast() }
                    }
            }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch app.screen {
        case .start:    StartView(app: app)
        case .scanning: ScanningView(app: app)
        case .overview: OverviewView(app: app)
        case .drill:    DrillView(app: app)
        case .groups:   GroupsView(app: app)
        case .types:    TypesView(app: app)
        case .history:  HistoryView(app: app)
        case .settings: SettingsView(app: app)
        }
    }
}

#Preview {
    RootView(app: AppModel.previewStart)
        .frame(width: 1280, height: 820)
}
