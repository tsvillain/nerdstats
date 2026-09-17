import Foundation

// `nerdstats --dump` prints one full snapshot to the terminal instead of starting the menu
// bar app. Handy for checking which sensors a Mac exposes and for bug reports.
if CommandLine.arguments.contains("--dump") {
    DumpCommand.run()
} else {
    MainActor.assumeIsolated { NerdStatsApp.main() }
}
