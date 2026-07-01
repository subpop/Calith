// Copyright 2026 Link Dupont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import SwiftData

@main
struct CalithApp: App {
    @StateObject private var updater = SoftwareUpdater()

    var sharedModelContainer: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        #if DEBUG
        let storeURL = appSupport
            .appendingPathComponent("app.subpop.Calith")
            .appendingPathComponent("CalithDebug.store")
        #else
        let storeURL = appSupport
            .appendingPathComponent("app.subpop.Calith")
            .appendingPathComponent("Calith.store")
        #endif
        
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        
        let schema = Schema(versionedSchema: CalithSchemaV1.self)
        let modelConfiguration = ModelConfiguration(url: storeURL)

        do {
            return try ModelContainer(for: schema, migrationPlan: CalithMigrationPlan.self, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ConversationView()
        }
        .modelContainer(sharedModelContainer)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 360, height: 440)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView(updater: updater)
                .modelContainer(sharedModelContainer)
        }
    }
}
