# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the Mac invitation with the same wire messages used by Windows."""

import base64
import hashlib
import hmac
import pathlib
import socket
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVER = bytes(range(32))
CLIENT = bytes(reversed(range(32)))


def read_exact(connection, count):
    received = bytearray()
    while len(received) < count:
        chunk = connection.recv(count - len(received))
        if not chunk:
            raise AssertionError("The pairing reply ended early")
        received.extend(chunk)
    return received


def main():
    with tempfile.TemporaryDirectory() as directory:
        fixture = pathlib.Path(directory) / "main.swift"
        executable = fixture.with_name("pairing")
        fixture.write_text(
            """import Foundation
let invitation = try WorkstationPairingCode(
    host: "127.0.0.1",
    fingerprint: "SERVER_PIN"
)!
invitation.start(onCode: { print($0); fflush(stdout) },
                 onEnd: { _ in exit(1) }) { pin, completion in
    completion(pin == "CLIENT_PIN")
}
dispatchMain()
""".replace("SERVER_PIN", SERVER.hex()).replace("CLIENT_PIN", CLIENT.hex()),
            encoding="utf-8",
        )
        source = ROOT / "Sources/Vorssaint/Services/Display/WorkstationPairingCode.swift"
        subprocess.run(["swiftc", str(source), str(fixture), "-o", str(executable)], check=True, timeout=90)
        process = subprocess.Popen([str(executable)], stdout=subprocess.PIPE, text=True)
        try:
            # The fixture kills itself on listener failure or expiration.
            code = process.stdout.readline().strip()
            assert len(code) == 30
            invitation = base64.urlsafe_b64decode(code + "==")
            host = socket.inet_ntoa(invitation[:4])
            port = int.from_bytes(invitation[4:6], "big")
            secret = invitation[6:]
            request = CLIENT + hmac.digest(secret, b"workstation pairing request v1" + CLIENT, hashlib.sha256)
            with socket.create_connection((host, port), timeout=8) as connection:
                connection.sendall(CLIENT + bytes(32))
                assert connection.recv(1) == b"", "An invalid proof received a reply"
            with socket.create_connection((host, port), timeout=8) as connection:
                connection.sendall(request)
                expected = hmac.digest(secret, b"workstation pairing reply v1" + CLIENT + SERVER, hashlib.sha256)
                assert read_exact(connection, 64) == SERVER + expected
        finally:
            process.terminate()
            process.wait(timeout=10)
    print("WORKSTATION PAIRING INTEGRATION TESTS OK")


if __name__ == "__main__":
    main()
