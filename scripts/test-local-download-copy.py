#!/usr/bin/env python3
"""Compile exact production local-copy fragments against an isolated temp folder."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'Nova/Services/DownloadManager.swift').read_text()
def method(signature):
    start=source.index(signature); brace=source.index('{',start); end=brace+1; depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}'); end+=1
    return source[start:end].replace('private static func','static func')
fragments='\n'.join(method(x) for x in ['nonisolated private static func stageLocalCopy(', 'nonisolated private static func destinationURL(', 'nonisolated private static func fileSize(', 'nonisolated private static func cleanupAbandonedStaging('])
harness='import Foundation\nstruct Fixture {\nnonisolated static let mediaFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)\n'+fragments+r'''
}
@main struct Checks {
    static func main() async throws {
        let root=Fixture.mediaFolder
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source=root.appendingPathComponent("source.mp4")
        let bytes=Data(repeating: 7, count: 3*1_024*1_024+19); try bytes.write(to: source)
        let id=UUID(); let destination=try Fixture.destinationURL(id:id,sourceURL:source)
        let original=Data([1,2,3]); try original.write(to:destination)
        let copied=try Fixture.stageLocalCopy(id:id,source:source)
        let stagedBytes=try Data(contentsOf:copied.staged), existingBytes=try Data(contentsOf:destination)
        precondition(stagedBytes==bytes && copied.size==Int64(bytes.count) && existingBytes==original)
        try FileManager.default.removeItem(at:copied.staged)
        let empty=root.appendingPathComponent("empty.mp4"); try Data().write(to:empty)
        do { _=try Fixture.stageLocalCopy(id:UUID(),source:empty); preconditionFailure("empty source accepted") } catch {}
        let cancelled=Task.detached { try Fixture.stageLocalCopy(id:UUID(),source:source) }
        cancelled.cancel()
        do { _=try await cancelled.value; preconditionFailure("cancelled copy accepted") } catch is CancellationError {}
        let orphan=root.appendingPathComponent("\(UUID()).\(UUID()).pending")
        try Data([1]).write(to:orphan)
        try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(-100_000)],ofItemAtPath:orphan.path)
        let unrelated=root.appendingPathComponent("leave-me.pending"); try Data([1]).write(to:unrelated)
        Fixture.cleanupAbandonedStaging()
        precondition(!FileManager.default.fileExists(atPath:orphan.path) && FileManager.default.fileExists(atPath:unrelated.path))
        print("PASS: production chunked local copy, preserved destination, empty/cancelled rejection, narrowly owned orphan cleanup")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nova-local-copy-') as temp:
    path=Path(temp)/'checks.swift'; path.write_text(harness)
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(root/'Nova/Services/MediaReliabilityPolicy.swift'),str(path),'-o',str(Path(temp)/'checks')],check=True)
    subprocess.run([str(Path(temp)/'checks')],check=True)
