import Foundation
import Network
import Observation
import OSLog

private let log = Logger(subsystem: "com.northwoodschurch.screentally", category: "TSL")

/// TSL UMD 5.0 / 3.1 TCP listener for Ross Carbonite switchers.
///
/// Listens on a TCP port for incoming connections from the Carbonite.
/// The Carbonite acts as a TCP client and connects to this listener.
@Observable
@MainActor
final class TSLListener {
    nonisolated init() { }

    // MARK: - Observable State

    /// True when the TCP listener is actively accepting connections
    private(set) var isListening = false

    /// True when a Carbonite (or other TSL source) has connected
    private(set) var isConnected = false

    /// Remote endpoint description when connected
    private(set) var connectedPeer: String?

    /// Human-readable description of the last error
    private(set) var lastError: String?

    /// All known sources from TSL data
    private(set) var sources: [Int: SourceInfo] = [:]

    // MARK: - Computed State

    /// The combined tally state for all monitored sources.
    /// Priority: program/previewProgram > preview > clear
    var monitoredTally: TallyState {
        let indices = AppSettings.shared.monitoredSourceIndices
        guard !indices.isEmpty else { return .clear }

        var hasProgram = false
        var hasPreview = false

        for index in indices {
            guard let source = sources[index] else { continue }
            switch source.tally {
            case .program, .previewProgram:
                hasProgram = true
            case .preview:
                hasPreview = true
            case .clear:
                break
            }
        }

        if hasProgram {
            return hasPreview ? .previewProgram : .program
        } else if hasPreview {
            return .preview
        }
        return .clear
    }

    /// Sorted list of sources for the picker
    var sortedSources: [SourceInfo] {
        sources.values.sorted { $0.index < $1.index }
    }

    // MARK: - Private State

    private var listener: NWListener?
    private var connection: NWConnection?
    private var dataBuffer = Data()
    private var listeningPort: UInt16 = 0

    // MARK: - Lifecycle

    /// Starts listening for incoming TSL connections on the given port
    func startListening(port: UInt16) {
        stopListening()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port: \(port)"
            log.error("Invalid port number: \(port)")
            return
        }

        listeningPort = port

        do {
            let newListener = try NWListener(using: .tcp, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            newListener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    self?.handleIncomingConnection(conn)
                }
            }

            newListener.start(queue: .main)
            listener = newListener

            log.info("TSL listener starting on port \(port)")
        } catch {
            lastError = "Failed to start listener: \(error.localizedDescription)"
            log.error("TSL listener failed to start: \(error.localizedDescription)")
        }
    }

    /// Tears down the listener and any active connection
    func stopListening() {
        connection?.cancel()
        connection = nil
        connectedPeer = nil

        listener?.cancel()
        listener = nil

        dataBuffer.removeAll()
        isListening = false
        isConnected = false
        lastError = nil

        log.info("TSL listener stopped")
    }

    /// Restarts the listener with the current port setting
    func restart() {
        startListening(port: UInt16(AppSettings.shared.port))
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            lastError = nil
            log.info("TSL listener ready on port \(self.listeningPort)")

        case .failed(let error):
            log.error("TSL listener failed: \(error.localizedDescription)")
            lastError = "Listener failed: \(error.localizedDescription)"
            isListening = false

        case .cancelled:
            log.info("TSL listener cancelled")
            isListening = false

        case .waiting(let error):
            log.warning("TSL listener waiting: \(error.localizedDescription)")
            lastError = "Waiting: \(error.localizedDescription)"

        case .setup:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Incoming Connections

    private func handleIncomingConnection(_ conn: NWConnection) {
        // Replace any existing connection
        if let old = connection {
            log.info("TSL replacing existing connection")
            old.cancel()
        }

        connection = conn
        dataBuffer.removeAll()
        sources.removeAll()

        // Describe the remote peer
        if case .hostPort(let host, let port) = conn.endpoint {
            connectedPeer = "\(host):\(port)"
            log.info("TSL incoming connection from \(self.connectedPeer ?? "unknown")")
        } else {
            connectedPeer = conn.endpoint.debugDescription
        }

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, connection: conn)
            }
        }

        conn.start(queue: .main)
        receiveLoop(on: conn)
    }

    // MARK: - Connection State

    private func handleConnectionState(_ state: NWConnection.State, connection conn: NWConnection) {
        switch state {
        case .ready:
            isConnected = true
            lastError = nil
            log.info("TSL connection ready")

        case .failed(let error):
            log.error("TSL connection failed: \(error.localizedDescription)")
            cleanUpConnection(conn)

        case .cancelled:
            log.info("TSL connection cancelled")
            cleanUpConnection(conn)

        case .preparing, .setup:
            break

        case .waiting(let error):
            log.warning("TSL connection waiting: \(error.localizedDescription)")

        @unknown default:
            break
        }
    }

    private func cleanUpConnection(_ conn: NWConnection) {
        if connection === conn {
            connection = nil
            connectedPeer = nil
            isConnected = false
            dataBuffer.removeAll()
        }
    }

    // MARK: - Receive Loop

    private func receiveLoop(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    log.error("TSL receive error: \(error.localizedDescription)")
                    self.lastError = "Receive error: \(error.localizedDescription)"
                    return
                }

                if let data, !data.isEmpty {
                    self.dataBuffer.append(data)
                    self.processBuffer()
                }

                if isComplete {
                    log.info("TSL connection stream completed")
                    self.cleanUpConnection(conn)
                } else {
                    self.receiveLoop(on: conn)
                }
            }
        }
    }

    // MARK: - Protocol Detection & Parsing

    /// Drains the TCP stream buffer, extracting and parsing complete TSL messages
    private func processBuffer() {
        while dataBuffer.count >= 4 {
            let bytes = [UInt8](dataBuffer.prefix(4))
            let pbc = Int(bytes[0]) | (Int(bytes[1]) << 8)  // little-endian 16-bit
            let version = bytes[2]

            // TSL 5.0: PBC in [10, 1000], version == 0x00
            let totalMessageLength = pbc + 2
            if pbc >= 10 && pbc <= 1000 && version == 0x00 && totalMessageLength <= dataBuffer.count {
                let messageData = Data(dataBuffer.prefix(totalMessageLength))
                dataBuffer.removeFirst(totalMessageLength)
                parseTSL5(messageData)
                continue
            }

            // TSL 3.1 fallback: fixed 18-byte messages
            if pbc > 1000 && dataBuffer.count >= 18 {
                let messageData = Data(dataBuffer.prefix(18))
                dataBuffer.removeFirst(18)
                parseTSL31(messageData)
                continue
            }

            // Incomplete or unrecognizable data
            if pbc > 1000 || totalMessageLength > dataBuffer.count {
                if pbc > 1000 {
                    log.warning("Clearing TSL buffer: unrecognised framing")
                    dataBuffer.removeAll()
                }
                break
            }

            break
        }
    }

    // MARK: - TSL 5.0 Parser

    private func parseTSL5(_ data: Data) {
        guard data.count >= 12 else {
            log.warning("TSL 5.0 message too short")
            return
        }

        let index   = Int(data[6]) | (Int(data[7]) << 8)
        let control = Int(data[8]) | (Int(data[9]) << 8)

        // Tally brightness levels (0-3 per tally):
        //   bits 0-1  = Tally 1 (Program / Red)
        //   bits 2-3  = Tally 2 (Preview / Green)
        let programBrightness = control & 0x03
        let previewBrightness = (control >> 2) & 0x03

        let tally = tallyState(program: programBrightness > 0, preview: previewBrightness > 0)

        // Extract label text
        var displayText = ""
        if data.count > 12 {
            let textLength = Int(data[10]) | (Int(data[11]) << 8)
            let textEnd = 12 + textLength
            if textLength > 0 && data.count >= textEnd {
                let textData = data[12 ..< textEnd]

                if let utf8 = String(data: textData, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces),
                   !utf8.isEmpty {
                    displayText = utf8
                } else if let utf16 = String(data: textData, encoding: .utf16LittleEndian)?
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces),
                   !utf16.isEmpty {
                    displayText = utf16
                }
            }
        }

        // Parse Carbonite label format: sourceIndex:busLabel:sourceLabel
        let label = parseLabel(displayText)

        updateSource(index: index, label: label, tally: tally)
    }

    // MARK: - TSL 3.1 Parser

    private func parseTSL31(_ data: Data) {
        guard data.count >= 18 else {
            log.warning("TSL 3.1 message too short")
            return
        }

        let address = Int(data[0])
        let control = data[1]

        let programBrightness = Int(control & 0x03)
        let previewBrightness = Int((control >> 2) & 0x03)

        let tally = tallyState(program: programBrightness > 0, preview: previewBrightness > 0)

        // 16-char display field
        let textData = data[2 ..< 18]
        let displayText = String(data: textData, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .whitespaces) ?? ""

        // TSL 3.1 addresses are 0-based; convert to 1-based
        let index = address + 1
        let label = parseLabel(displayText)

        updateSource(index: index, label: label, tally: tally)
    }

    // MARK: - Helpers

    private func tallyState(program: Bool, preview: Bool) -> TallyState {
        switch (program, preview) {
        case (true, true):
            return .previewProgram
        case (true, false):
            return .program
        case (false, true):
            return .preview
        case (false, false):
            return .clear
        }
    }

    /// Parses Carbonite label format: `sourceIndex:busLabel:sourceLabel`
    private func parseLabel(_ text: String) -> String {
        let parts = text.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 3 else {
            return text
        }
        // Return just the source label (last part)
        return parts[2]
    }

    private func updateSource(index: Int, label: String, tally: TallyState) {
        sources[index] = SourceInfo(index: index, label: label, tally: tally)
    }
}
