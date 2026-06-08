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

    private let parserQueue = DispatchQueue(label: "io.github.xun66.icloudsyncwatch.parser")
    private let processQueue = DispatchQueue(label: "io.github.xun66.icloudsyncwatch.process")
    private let parser: LiveLogParser
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var bufferedText = ""
    private var errorOutput = Data()
    private var isStoppingProcess = false

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
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            self.errorOutput = Data()

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

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else {
                    return
                }
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }
                self.processQueue.async {
                    self.errorOutput.append(data)
                }
            }

            process.terminationHandler = { [weak self] process in
                guard let self else {
                    return
                }
                self.processQueue.async {
                    let wasStoppingProcess = self.isStoppingProcess
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.errorPipe?.fileHandleForReading.readabilityHandler = nil
                    let errorMessage = Self.failureMessage(
                        terminationStatus: process.terminationStatus,
                        stderr: self.errorOutput
                    )
                    self.process = nil
                    self.outputPipe = nil
                    self.errorPipe = nil
                    self.errorOutput = Data()
                    self.isStoppingProcess = false
                    if !wasStoppingProcess, process.terminationStatus != 0 {
                        Task { @MainActor in
                            self.onFailure?(errorMessage)
                        }
                    }
                }
            }

            do {
                try process.run()
                self.process = process
                self.outputPipe = outputPipe
                self.errorPipe = errorPipe
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self.onFailure?(L10n.tr("error.logStreamStartFailed", error.localizedDescription))
                }
            }
        }
    }

    func stop() {
        processQueue.async {
            guard let process = self.process else {
                return
            }
            self.isStoppingProcess = true
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            self.errorPipe?.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            self.process = nil
            self.outputPipe = nil
            self.errorPipe = nil
            self.bufferedText = ""
            self.errorOutput = Data()
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

    private static func failureMessage(terminationStatus: Int32, stderr: Data) -> String {
        let trimmedStderr = String(data: stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if terminationStatus == 77 {
            if let trimmedStderr, !trimmedStderr.isEmpty {
                return L10n.tr("error.logStreamPermissionDeniedWithDetail", trimmedStderr)
            }
            return L10n.tr("error.logStreamPermissionDenied")
        }

        if let trimmedStderr, !trimmedStderr.isEmpty {
            return L10n.tr("error.logStreamExitedWithDetail", terminationStatus, trimmedStderr)
        }

        return L10n.tr("error.logStreamExited", terminationStatus)
    }
}
