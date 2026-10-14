import AppKit

enum ApplicationTermination {
    /// Retain the NSRunningApplication instance captured with the tile. Looking
    /// up its old PID here could instead target a newly launched process.
    static func request(_ app: NSRunningApplication?) -> String? {
        guard let app, !app.isTerminated else { return "앱이 이미 종료되었습니다." }
        guard app != NSRunningApplication.current else { return "Tile Launcher 자체는 메뉴 막대에서 종료해 주세요." }
        // Success means the normal request was sent, not that the app exited.
        // Workspace termination notifications update the inventory after exit.
        return app.terminate() ? nil : "앱에 종료 요청을 보내지 못했습니다. 앱에서 직접 종료해 주세요."
    }
}
