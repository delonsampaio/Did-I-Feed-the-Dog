import AppIntents
import SwiftUI
import WidgetKit

struct LogFeedingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.delon.DidIFeedTheDog.LogFeedingControl"
        ) {
            ControlWidgetButton(action: OpenLogFeedingIntent()) {
                Label("Log Feeding", systemImage: "dog.fill")
            }
        }
        .displayName("Log Feeding")
        .description("Open Did I Feed the Dog? to quickly log a meal.")
    }
}

struct OpenLogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Feeding"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
