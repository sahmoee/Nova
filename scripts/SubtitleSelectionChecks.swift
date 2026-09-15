import Foundation

@main enum SubtitleSelectionChecks {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); count += 1 }
        var gate = SubtitleSelectionGate()
        let startup = gate.revision
        let first = gate.begin("English")
        check(gate.accepts(first), "First request is pending")
        check(startup != gate.revision, "Manual request retires startup auto-selection")
        gate.cancel() // Off or sheet dismissal while a download is suspended.
        check(!gate.accepts(first), "Late download cannot re-enable subtitles after Off")
        check(!gate.finish(first) && gate.pendingID == nil, "Late completion cannot publish a selection")
        let second = gate.begin("English")
        let third = gate.begin("Spanish")
        check(!gate.accepts(second) && gate.accepts(third), "Newer language wins")
        check(!gate.finish(second) && gate.pendingID == "Spanish", "Old failure cannot clear new spinner")
        check(gate.finish(third) && gate.pendingID == nil, "Only applied current request can finish")
        check(!gate.accepts(third) && !gate.finish(third), "Double callback cannot apply twice")
        let fourth = gate.begin("Imported file")
        gate.cancel() // Leaving playback.
        let fifth = gate.begin("Another file")
        check(fourth != fifth && !gate.finish(fourth), "Restart cannot revive prior file choice")
        check(gate.pendingID == "Another file", "Old finalizer preserves current choice")
        gate.cancel(); gate.cancel()
        check(!gate.accepts(fifth), "Repeated cancel remains safe")
        for (value, expected) in [(0.0, 0.5), (-100.0, 0.5), (10.0, 2.5), (1.0, 1.0), (1.29999999, 1.3), (Double.nan, 1.0), (.infinity, 1.0), (-Double.infinity, 1.0)] {
            check(SubtitleScalePolicy.normalized(value) == expected, "Stored scale is finite, bounded, and rounded")
        }
        var scale = 1.0
        for _ in 0..<30 { scale = SubtitleScalePolicy.normalized(scale + 0.1) }
        check(scale == SubtitleScalePolicy.range.upperBound, "Repeated larger reaches exact disabled limit")
        for _ in 0..<30 { scale = SubtitleScalePolicy.normalized(scale - 0.1) }
        check(scale == SubtitleScalePolicy.range.lowerBound, "Repeated smaller reaches exact disabled limit")
        print("Subtitle selection checks passed: \(count)")
    }
}
