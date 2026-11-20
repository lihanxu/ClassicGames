import XCTest

/// 把模拟器当前画面存到练习工程的媒体目录，供阶段验收留图。
enum Screenshot {
    static func save(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let directory = URL(fileURLWithPath: "/Users/hansen/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-320a8ba5-8d5a-47a5-aa12-3bea319d4ab1/files/media", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name))
        } catch {
            XCTFail("截图写入失败 \(name)：\(error)", file: file, line: line)
        }
    }
}
