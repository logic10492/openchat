import Foundation

struct SSEEvent: Sendable, Equatable {
    let eventType: String?
    let data: String
}

struct SSEStreamParser {
    static func parse(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        parse(sequence: bytes)
    }

    static func parse<S: AsyncSequence>(sequence: S) -> AsyncThrowingStream<SSEEvent, Error> where S.Element == UInt8 {
        return AsyncThrowingStream { continuation in
            let pump = Pump(iterator: sequence.makeAsyncIterator())
            let task = Task {
                do {
                    while let event = try await pump.nextEvent() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private final class Pump<Iterator: AsyncIteratorProtocol>: @unchecked Sendable where Iterator.Element == UInt8 {
    private enum LineAction {
        case none
        case event(SSEEvent)
        case finish
    }

    private var iterator: Iterator
    private var currentLine: [UInt8] = []
    private var currentDataLines: [String] = []
    private var currentEventType: String?
    private var isFinished = false

    init(iterator: Iterator) {
        self.iterator = iterator
    }

    func nextEvent() async throws -> SSEEvent? {
        guard !isFinished else {
            return nil
        }

        while let byte = try await iterator.next() {
            if byte == 10 {
                let action = processLine(currentLine)
                currentLine.removeAll(keepingCapacity: true)
                switch action {
                case .none:
                    continue
                case .event(let event):
                    return event
                case .finish:
                    isFinished = true
                    return nil
                }
            } else {
                currentLine.append(byte)
            }
        }

        let terminalAction = processLine(currentLine)
        currentLine.removeAll(keepingCapacity: true)
        switch terminalAction {
        case .none:
            isFinished = true
            if currentDataLines.isEmpty {
                return nil
            }
            return flushCurrentEvent()
        case .event(let event):
            isFinished = true
            return event
        case .finish:
            isFinished = true
            return nil
        }
    }

    private func processLine(_ rawBytes: [UInt8]) -> LineAction {
        guard !rawBytes.isEmpty else {
            return flushAction()
        }

        let line = String(decoding: rawBytes, as: UTF8.self).trimmingCharacters(in: .init(charactersIn: "\r"))
        guard !line.isEmpty else {
            return flushAction()
        }

        if line.hasPrefix(":") {
            return .none
        }

        if line == "data: [DONE]" {
            return .finish
        }

        if line.hasPrefix("event:") {
            let value = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            currentEventType = String(value)
            return .none
        }

        if line.hasPrefix("data:") {
            let value = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            currentDataLines.append(String(value))
        }

        return .none
    }

    private func flushAction() -> LineAction {
        guard let event = flushCurrentEvent() else {
            return .none
        }
        return .event(event)
    }

    private func flushCurrentEvent() -> SSEEvent? {
        guard !currentDataLines.isEmpty else {
            currentEventType = nil
            return nil
        }
        let eventType = currentEventType
        defer {
            currentDataLines.removeAll(keepingCapacity: true)
            currentEventType = nil
        }
        return SSEEvent(eventType: eventType, data: currentDataLines.joined(separator: "\n"))
    }
}
