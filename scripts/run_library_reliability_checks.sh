#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fixture_binary="$(mktemp -t nova-library-checks)"
trap 'rm -f "$fixture_binary"' EXIT
swiftc -parse-as-library Nova/Models/SourceType.swift Nova/Models/CatalogModels.swift \
 Nova/Models/StreamModels.swift Nova/Models/MediaItem.swift Nova/Models/MediaCollection.swift \
 Nova/Utilities/LanguageNames.swift Nova/Services/MediaReliabilityPolicy.swift \
 Nova/Services/LibraryMutationPolicy.swift Nova/Services/LibraryFilePolicy.swift \
 Nova/Services/LibraryStore.swift scripts/LibraryReliabilityChecks.swift -o "$fixture_binary"
"$fixture_binary"
