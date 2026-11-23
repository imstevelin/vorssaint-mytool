// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import Network

/// The invitation carries the endpoint and 128 bits of entropy. Only certificate
/// fingerprints cross this connection. Deskflow still authenticates both peers over TLS.
final class WorkstationPairingCode {
    private let listener: NWListener
    private let address: [UInt8]
    private let serverPin: Data
    private let secret = SymmetricKey(size: .bits128)
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var expiry: DispatchWorkItem?
    private var acceptedPin: Data?
    private var pinSaved = false

    init?(host: String, fingerprint: String) throws {
        address = host.split(separator: ".").compactMap { UInt8($0) }
        guard address.count == 4, fingerprint.count == 64, let pin = Self.decodePin(fingerprint) else { return nil }
        serverPin = pin
        listener = try NWListener(using: .tcp)
    }

    func start(onCode: @escaping (String) -> Void, onEnd: @escaping (Error?) -> Void,
               accept: @escaping (String, @escaping (Bool) -> Void) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = self.listener.port?.rawValue else { return }
                var bytes = Data(self.address + [UInt8(port >> 8), UInt8(truncatingIfNeeded: port)])
                self.secret.withUnsafeBytes { bytes.append(contentsOf: $0) }
                let code = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                onCode(code)
            case let .failed(error):
                self.cancel()
                onEnd(error)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 8 else { connection.cancel(); return }
            let id = ObjectIdentifier(connection)
            self.connections[id] = connection
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.close(id) }
            connection.receive(minimumIncompleteLength: 64, maximumLength: 64) { [weak self] data, _, _, _ in
                guard let self, self.connections[id] != nil, let data, data.count == 64 else {
                    self?.close(id)
                    return
                }
                let clientPin = Data(data.prefix(32))
                let request = Data("workstation pairing request v1".utf8) + clientPin
                guard HMAC<SHA256>.isValidAuthenticationCode(data.suffix(32), authenticating: request, using: self.secret) else {
                    self.close(id)
                    return
                }
                let reply = {
                    let message = Data("workstation pairing reply v1".utf8) + clientPin + self.serverPin
                    let mac = HMAC<SHA256>.authenticationCode(for: message, using: self.secret)
                    connection.send(content: self.serverPin + Data(mac), completion: .contentProcessed { _ in self.close(id) })
                }
                if self.acceptedPin == clientPin, self.pinSaved { reply(); return }
                guard self.acceptedPin == nil else { self.close(id); return }
                self.acceptedPin = clientPin
                accept(clientPin.map { String(format: "%02x", $0) }.joined()) { success in
                    guard success else { self.acceptedPin = nil; self.close(id); return }
                    self.pinSaved = true
                    reply()
                }
            }
        }
        let expiry = DispatchWorkItem { [weak self] in
            self?.cancel()
            onEnd(nil)
        }
        self.expiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: expiry)
        listener.start(queue: .main)
    }

    func cancel() {
        expiry?.cancel()
        listener.cancel()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func close(_ id: ObjectIdentifier) { connections.removeValue(forKey: id)?.cancel() }

    private static func decodePin(_ text: String) -> Data? {
        let digits = Array(text)
        let bytes = stride(from: 0, to: digits.count, by: 2).compactMap {
            UInt8(String(digits[$0...($0 + 1)]), radix: 16)
        }
        return bytes.count == 32 ? Data(bytes) : nil
    }
}
