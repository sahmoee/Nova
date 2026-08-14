import Foundation

// Compatibility entry point. The Python generator owns the shared iOS/tvOS
// asset pipeline because it can reliably extract a transparent tvOS foreground.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let script = root.appendingPathComponent("generate_brand_assets.py")

guard FileManager.default.fileExists(atPath: script.path) else {
    fatalError("Missing brand generator at \(script.path)")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["python3", script.path] + Array(CommandLine.arguments.dropFirst())
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("Brand asset generation failed with status \(process.terminationStatus)")
}
