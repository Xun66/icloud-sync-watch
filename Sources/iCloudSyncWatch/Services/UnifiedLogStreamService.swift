import Foundation

protocol LogStreamControlling: AnyObject {
    var onEvents: (([ParsedSyncEvent]) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start()
    func stop()
}

final class UnifiedLogStreamService: @unchecked Sendable, LogStreamControlling {
    var onEvents: (([ParsedSyncEvent]) -> Void)?
    var onFailure: ((String) -> Void)?

    private let parserQueue = DispatchQueue(label: "labs.mindive.icloudsyncwatch.parser")
    private let processQueue = DispatchQueue(label: "labs.mindive.icloudsyncwatch.process")
    private let parser: LiveLogParser
    private var process: Process?
    private var outputPipe: Pipe?
    private var bufferedText = ""

    init(parser: LiveLogParser) {
        self.parser = parser
    }

    func start() {
        processQueue.async {
            guard self.process == nil else {
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "stream",
                "--style",
                "compact",
                "--level",
                "debug",
                "--predicate",
                #"(process == "fileproviderd") OR (process == "com.apple.CloudDocs.iCloudDriveFileProvider")"#,
            ]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else {
                    return
                }
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }
                self.consume(data: data)
            }

            process.terminationHandler = { [weak self] process in
                guard let self else {
                    return
                }
                self.processQueue.async {
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.process = nil
                    self.outputPipe = nil
                    if process.terminationStatus != 0, process.terminationReason != .exit {
                        Task { @MainActor in
                            self.onFailure?("`log stream` 异常退出，退出码 \(process.terminationStatus)")
                        }
                    }
                }
            }

            do {
                try process.run()
                self.process = process
                self.outputPipe = outputPipe
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self.onFailure?("无法启动 `/usr/bin/log stream`: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        processQueue.async {
            guard let process = self.process else {
                return
            }
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            self.process = nil
            self.outputPipe = nil
            self.bufferedText = ""
        }
    }

    private func consume(data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return
        }

        parserQueue.async {
            self.bufferedText.append(chunk)
            let parts = self.bufferedText.components(separatedBy: "\n")
            self.bufferedText = parts.last ?? ""

            for line in parts.dropLast() {
                let events = self.parser.feed(line: line, timestamp: Date())
                guard !events.isEmpty else {
                    continue
                }
                let callback = self.onEvents
                Task { @MainActor in
                    callback?(events)
                }
            }
        }
    }
}
