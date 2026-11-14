import SwiftUI

@main
struct DroidDeskApp: App {
    @State private var navigation = NavigationModel()

    var body: some Scene {
        Window("DroidDesk", id: "main") {
            RootView()
                .environment(navigation)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(AppSection.allCases) { section in
                    if let shortcut = section.viewMenuShortcut {
                        Toggle(section.title, isOn: Binding(
                            get: { navigation.section == section },
                            set: { isOn in
                                if isOn { navigation.show(section) }
                            }
                        ))
                        .keyboardShortcut(shortcut, modifiers: .command)
                    }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    navigation.show(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
