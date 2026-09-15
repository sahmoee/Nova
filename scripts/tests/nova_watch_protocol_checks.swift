import Foundation

@main struct Checks {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ label: String) { count += 1; precondition(condition, label) }
        func rejects(_ label: String, _ operation: () throws -> Void) { count += 1; do { try operation(); fatalError("Accepted: \(label)") } catch {} }
        let phone = UUID(), watch = UUID(), titleID = UUID(), now = Date()
        var title = NovaWatchTitle(id: titleID, title: "Synthetic Film", subtitle: "2026", planKey: String(repeating: "a", count: 64), duration: 7200, position: 100,
            favorite: false, queued: false, watched: false, lastPlayed: now, isSeries: false, resumeAvailable: true)
        let snapshot = NovaWatchSnapshot(phoneID: phone, revision: 8, generatedAt: now, totalTitles: 60000, titles: [title], plans: [], totalPlans: 0, phoneForeground: true)
        try NovaWatchCodec.validate(snapshot); check(snapshot.titles.count == 1 && snapshot.totalTitles == 60000, "bounded snapshot keeps true total")
        let encoded = try NovaWatchCodec.encode(NovaWatchEnvelope(snapshot: snapshot))
        check(!String(decoding: encoded, as: UTF8.self).contains("http"), "projection excludes URLs")
        check(try NovaWatchCodec.decode(NovaWatchEnvelope.self, data: encoded).snapshot == snapshot, "snapshot round trip")
        var older = snapshot; older.revision = 7
        check(NovaWatchPolicy.decision(incoming: older, current: snapshot, correlatedRefresh: false) == .ignore, "ignore stale same epoch")
        check(NovaWatchPolicy.decision(incoming: snapshot, current: older, correlatedRefresh: false) == .advance, "accept later same epoch")
        var reset = snapshot; reset.phoneID = UUID(); reset.revision = 0
        check(NovaWatchPolicy.decision(incoming: reset, current: snapshot, correlatedRefresh: false) == .ignore, "unsolicited epoch cannot overwrite")
        check(NovaWatchPolicy.decision(incoming: reset, current: snapshot, correlatedRefresh: true) == .replace, "correlated reset accepted")
        check(NovaWatchPolicy.decision(incoming: snapshot, current: reset, correlatedRefresh: false) == .ignore, "delayed old epoch cannot return")
        check(NovaWatchPolicy.decision(incoming: snapshot, current: nil, correlatedRefresh: false) == .replace, "first offline context can seed")
        check(NovaWatchPolicy.live(snapshot, reachable: true, now: now), "fresh foreground live")
        check(!NovaWatchPolicy.live(snapshot, reachable: false, now: now), "unreachable cannot control")
        check(!NovaWatchPolicy.live(snapshot, reachable: true, now: now.addingTimeInterval(21)), "stale cannot control")
        var background = snapshot; background.phoneForeground = false
        check(!NovaWatchPolicy.live(background, reachable: true, now: now), "background cannot control")
        let command = NovaWatchCommand(watchID: watch, phoneID: phone, sequence: 1, action: .setFavorite, itemID: titleID, flag: true)
        try command.validate()
        check(NovaWatchPolicy.overlay(title, commands: [command], phoneID: phone).favorite, "pending favorite overlays old snapshot")
        check(!NovaWatchPolicy.overlay(title, commands: [command], phoneID: reset.phoneID).favorite, "old epoch overlay isolated")
        var second = command; second.id = UUID(); second.sequence = 2; second.flag = false
        check(!NovaWatchPolicy.overlay(title, commands: [command, second], phoneID: phone).favorite, "latest explicit set wins")
        var watched = command; watched.action = .setWatched
        title.queued = true
        let applied = NovaWatchPolicy.overlay(title, commands: [watched], phoneID: phone)
        check(applied.watched && !applied.queued, "mark watched queue semantics")
        watched.flag = false
        let cleared = NovaWatchPolicy.overlay(title, commands: [watched], phoneID: phone)
        check(!cleared.watched && cleared.position == 0 && !cleared.hasResume && cleared.lastPlayed == nil, "clear progress overlay")
        var outbox = NovaWatchOutbox(watchID: watch)
        var first = try outbox.make(phoneID: phone, action: .setFavorite); first.itemID = titleID; first.flag = true
        outbox.commands.append(first)
        let transient = try outbox.make(phoneID: phone, action: .refresh)
        check(transient.sequence == 2 && outbox.commands.count == 1, "transient not durable")
        var next = try outbox.make(phoneID: phone, action: .setFavorite); next.itemID = titleID; next.flag = false; outbox.commands.append(next)
        try outbox.validate(); check(outbox.commands.first?.id == first.id && next.sequence == 3, "durable order survives transient gaps")
        var journal = NovaWatchJournal(phoneID: phone)
        try journal.reserve(first)
        check(journal.previous(first)?.outcome == .interrupted, "reservation persisted before mutation")
        let result = NovaWatchReceipt(id: first.id, outcome: .applied, message: "Applied")
        journal.finish(result); check(journal.previous(first) == result, "duplicate exact receipt")
        try journal.reserve(next); journal.finish(NovaWatchReceipt(id: next.id, outcome: .applied, message: "Applied"))
        check(journal.previous(first) == result, "old applied receipt retained")
        var old = first; old.id = UUID()
        check(journal.previous(old)?.outcome == .rejected, "evicted old sequence never replays")
        var wrongEpoch = next; wrongEpoch.phoneID = UUID()
        rejects("wrong epoch reserve") { try journal.reserve(wrongEpoch) }
        var remote = NovaWatchCommand(watchID: watch, phoneID: phone, sequence: 4, action: .setPlaying, playerSessionID: UUID(), flag: true)
        remote.createdAt = now.addingTimeInterval(-21)
        rejects("expired remote") { try remote.validate(now: now) }
        remote.createdAt = now.addingTimeInterval(6)
        rejects("future remote") { try remote.validate(now: now) }
        remote.createdAt = now
        try remote.validate(now: now); check(!remote.action.isDurable, "remote never queued")
        remote.action = .seek; remote.value = .infinity
        rejects("nonfinite seek") { try remote.validate(now: now) }
        remote.value = 2_147_001
        rejects("seek exceeds VLC integer bound") { try remote.validate(now: now) }
        remote.action = .setVolume; remote.value = 1.01
        rejects("out of range volume") { try remote.validate(now: now) }
        remote.action = .openOnPhone; remote.itemID = titleID; remote.createdAt = now.addingTimeInterval(-30)
        rejects("expired handoff") { try remote.validate(now: now) }
        var bad = command; bad.version = 9
        rejects("unknown schema") { try bad.validate() }
        bad = command; bad.itemID = nil
        rejects("missing title") { try bad.validate() }
        bad = command; bad.flag = nil
        rejects("missing bool") { try bad.validate() }
        bad = command; bad.text = String(repeating: "a", count: 101)
        rejects("oversized text") { try bad.validate() }
        bad = command; bad.action = .removePlanEntry; bad.planID = UUID(); bad.entryID = nil
        rejects("missing entry") { try bad.validate() }
        bad.entryID = UUID(); try bad.validate(); check(bad.action.isDurable, "remove unresolved plan entry")
        var invalid = snapshot; invalid.titles.append(title)
        rejects("duplicate title identities") { try NovaWatchCodec.validate(invalid) }
        invalid = snapshot; invalid.totalTitles = 0
        rejects("false total") { try NovaWatchCodec.validate(invalid) }
        invalid = snapshot; invalid.titles[0].duration = .nan
        rejects("invalid duration") { try NovaWatchCodec.validate(invalid) }
        invalid = snapshot; invalid.titles[0].planKey = "file:///private/source"
        rejects("private identity") { try NovaWatchCodec.validate(invalid) }
        rejects("oversized envelope") { _ = try NovaWatchCodec.decode(NovaWatchEnvelope.self, data: Data(repeating: 0, count: 60001)) }
        var page = result; page.search = Array(repeating: title, count: 26)
        rejects("oversized search page") { try NovaWatchPolicy.validate(page) }
        page.search = [title]; page.searchTotal = 0
        rejects("false search count") { try NovaWatchPolicy.validate(page) }
        page.searchTotal = 60000; try NovaWatchPolicy.validate(page); check(page.searchTotal == 60000, "full library page count retained")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nova-watch-checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("outbox.json")
        try NovaWatchCodec.write(outbox, to: file)
        let saved = try NovaWatchCodec.read(NovaWatchOutbox.self, from: file)!
        try saved.validate(); check(saved.commands.map(\.id) == outbox.commands.map(\.id) && saved.nextSequence == 4, "outbox disk restart exact UUID/order")
        let journalFile = folder.appendingPathComponent("journal.json")
        try NovaWatchCodec.write(journal, to: journalFile)
        check(try NovaWatchCodec.read(NovaWatchJournal.self, from: journalFile)!.previous(first) == result, "ack dedup after restart")
        let corrupt = Data("not json".utf8); try corrupt.write(to: file)
        rejects("corrupt file") { _ = try NovaWatchCodec.read(NovaWatchOutbox.self, from: file) }
        check(try Data(contentsOf: file) == corrupt, "corrupt original preserved")
        let link = folder.appendingPathComponent("link.json"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        rejects("symlink cache") { _ = try NovaWatchCodec.read(NovaWatchOutbox.self, from: link) }
        try Data(repeating: 0, count: 512001).write(to: file)
        rejects("oversize cache") { _ = try NovaWatchCodec.read(NovaWatchOutbox.self, from: file) }
        var full = NovaWatchOutbox(watchID: watch)
        for _ in 0..<100 { var c = try full.make(phoneID: phone, action: .setFavorite); c.itemID = titleID; c.flag = true; full.commands.append(c) }
        rejects("outbox full") { _ = try full.make(phoneID: phone, action: .setFavorite) }
        check(try full.make(phoneID: phone, action: .refresh).action == .refresh, "full outbox can refresh reset epoch")
        let other = NovaWatchTitle(id: UUID(), title: "Outside recent 120", subtitle: "", planKey: String(repeating: "b", count: 64), duration: nil, position: 0, favorite: true, queued: true, watched: false, lastPlayed: nil, isSeries: false, resumeAvailable: false)
        let patched = NovaWatchPolicy.applying(other, to: snapshot)
        check(patched.titles.first?.id == other.id && patched.titles.first?.favorite == true && patched.totalTitles == 60000, "ACK for uncached title becomes authoritative")
        check(NovaWatchPolicy.overlay(patched.titles.first!, commands: [], phoneID: phone).queued, "confirmed state survives outbox removal")
        var repeated = patched
        repeated = NovaWatchPolicy.applying(other, to: repeated)
        check(repeated.titles.filter { $0.id == other.id }.count == 1, "ACK projection deduplicates")
        var bigPlan = WatchNightPlan(name: String(repeating: "👨‍👩‍👧‍👦", count: 100))
        for _ in 0..<40 { bigPlan.entries.append(WatchNightEntry(titleID: String(repeating: "a", count: 64), title: NovaWatchPolicy.boundedText(String(repeating: "👨‍👩‍👧‍👦", count: 300), characters: 179, bytes: 400))) }
        try bigPlan.validate()
        var planReceipt = result; planReceipt.plan = bigPlan
        let largeEnvelope = try NovaWatchCodec.encode(NovaWatchEnvelope(snapshot: snapshot, receipt: planReceipt))
        check(largeEnvelope.count < 60000, "40-title Unicode plan stays transferable")
        let short = NovaWatchPolicy.boundedText("Exact", characters: 179, bytes: 400)
        check(short == "Exact", "short title unchanged")
        let long = NovaWatchPolicy.boundedText(String(repeating: "👨‍👩‍👧‍👦", count: 180), characters: 179, bytes: 400)
        check(long.utf8.count <= 403 && long.hasSuffix("…"), "UTF8 and character display bounds")
        print("Nova watch protocol: \(count) checks passed")
    }
}
