//
//  KobutaTap.swift
//  KobutaTap
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct KobutaTap: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.register()
        AppSettings.registerDefaults()
        GameState.migrateBestScores()
        SoundPlayer.shared.configure()
        Store.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: SoundPlayer.shared.resume()
            case .background: SoundPlayer.shared.pause()
            default: break
            }
        }
    }

    /// 撮影モード（ScreenshotDemo）のときは、撮る画面を開く
    @ViewBuilder private var rootView: some View {
        switch ScreenshotDemo.scene {
        case .home, nil:
            ContentView()
        }
    }
}
