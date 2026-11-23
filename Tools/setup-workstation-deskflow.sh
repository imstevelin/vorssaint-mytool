#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
umask 077

profile="$HOME/Library/Application Support/Vorssaint Workstation"
tls="$profile/tls"
mkdir -p "$tls"
pem="$tls/deskflow.pem"
if [[ ! -s "$pem" ]]; then
    temp="$(mktemp -d "$tls/certificate.XXXXXXXX")"
    trap 'rm -f "$temp/key.pem" "$temp/cert.pem"; rmdir "$temp"' EXIT
    /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 730 \
        -subj /CN=workstation-mac -keyout "$temp/key.pem" -out "$temp/cert.pem" 2>/dev/null
    cat "$temp/cert.pem" "$temp/key.pem" > "$pem"
fi
/usr/bin/openssl x509 -in "$pem" -noout -fingerprint -sha256 | sed 's/.*=//;s/://g' | tr 'A-F' 'a-f'

if [[ $# -eq 0 ]]; then exit 0; fi
pin="$(printf '%s' "$1" | tr -d ':' | tr 'A-F' 'a-f')"
if [[ $# -ne 1 || ! "$pin" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s\n' 'Supply the exact Windows SHA-256 fingerprint.' >&2
    exit 2
fi
printf 'v2:sha256:%s\n' "$pin" > "$tls/trusted-clients"
cat > "$profile/workstation.conf" <<'EOF'
section: options
    keystroke(Control+Alt+Shift+F9) = switchToNextScreen
end
EOF
cat > "$profile/Deskflow.conf" <<EOF
[core]
computerName=workstation-mac
port=24800
startedBefore=true
useHooks=true

[log]
level=INFO
toFile=true
file="$profile/deskflow-server.log"

[security]
tlsEnabled=true
checkPeerFingerprints=true
certificate="$pem"

[server]
enableClipboard=false
enableHeartbeat=true
heartbeat=3000
externalConfig=true
externalConfigFile="$profile/workstation.conf"
protocol=barrier

[computer_workstation-mac]
name=workstation-mac

[computer_workstation-windows]
name=workstation-windows
EOF
