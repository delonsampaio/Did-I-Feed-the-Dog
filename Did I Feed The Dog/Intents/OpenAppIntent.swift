import AppIntents

struct OpenLogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Feeding"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
