//
//  DeepChatApp.swift
//  DeepChat
//
//  应用入口
//

import SwiftUI

@main
struct DeepChatApp: App {

    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
    }
}
