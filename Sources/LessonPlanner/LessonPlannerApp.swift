import SwiftUI

private let isDesignCaptureLaunch = ProcessInfo.processInfo.environment["LESSONPLANNER_DESIGN_CAPTURE"] == "1"

@main
struct LessonPlannerApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(
                    minWidth: isDesignCaptureLaunch ? 1500 : 820,
                    minHeight: isDesignCaptureLaunch ? 950 : 560
                )
        }
        .defaultSize(
            width: isDesignCaptureLaunch ? 1500 : 900,
            height: isDesignCaptureLaunch ? 950 : 612
        )
    }
}
