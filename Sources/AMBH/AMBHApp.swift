import AMBHCore
import SwiftUI

@main
struct AMBHApp: App {
    @StateObject private var model: AppViewModel

    init() {
        let model = AppViewModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Text(model.menuBarText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
