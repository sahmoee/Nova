#!/bin/sh
set -eu
nova_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
nova_binary=$(mktemp -t nova-watch-checks)
trap 'rm -f "$nova_binary"' EXIT INT TERM
xcrun swiftc -O "$nova_root/Nova/Models/WatchNight.swift" "$nova_root/NovaWatchShared/NovaWatchProtocol.swift" "$nova_root/scripts/tests/nova_watch_protocol_checks.swift" -o "$nova_binary"
"$nova_binary"
