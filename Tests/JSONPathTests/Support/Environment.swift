import Foundation

func environment(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}

private let logLock = NSLock()

func appendLine(_ line: String, to path: String) {
    logLock.lock()
    defer { logLock.unlock() }
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    handle.seekToEndOfFile()
    handle.write(Data(line.utf8))
    handle.closeFile()
}
