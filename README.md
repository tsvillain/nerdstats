# NerdStats

Menu bar system monitor for macOS (Intel and Apple Silicon).

NerdStats lives in the menu bar, starts when you log in, and shows how your Mac is doing
in real time. The dashboard gives everyone a plain-language verdict (**Normal**, **Busy**,
**Hot**), and a **Nerd** switch reveals the raw numbers behind it.

Requires macOS 13 Ventura or later.

## What it shows

| Section | Everyone sees | Nerd mode adds |
| --- | --- | --- |
| This Mac | Model, chip, memory, macOS version, uptime | Model identifier, architecture (Apple Silicon/Intel, Rosetta), physical/logical and P/E core counts, hostname |
| Processor | Total usage with a 60-sample sparkline | User/system/idle split, 1/5/15-minute load averages, per-core bars, top processes by CPU |
| Graphics | GPU utilization with sparkline | Per-GPU utilization and memory in use |
| Memory | Used vs. total, memory pressure | App/wired/compressed/cached/free, swap, top processes by memory |
| Storage | Free space per volume, read/write speed | Read/write sparklines, bytes read/written since boot |
| Network | Connection type, download/upload speed | Local IPv4/IPv6, public IP (only when you click **Look up**), totals since boot |
| Battery | Charge, charging state, time remaining, health, system power draw | Cycle count, capacity vs. design, temperature, voltage, battery power, adapter wattage |
| Temperatures & Fans | Processor, graphics and battery temperature, fan speeds | Every individual sensor grouped by category, fan min/max RPM |

The battery section is hidden on Macs without a battery. Anything a particular Mac does not
report is shown as unavailable instead of a guessed value.

The menu bar item can show CPU usage, CPU temperature, both, memory usage, or just an
icon. Settings also cover launch at login (on by default), the refresh interval (1, 2, 5
or 10 seconds) and °C/°F.

## Build, run and test

You need Xcode (or the Xcode command line tools) with Swift 5.9 or newer. Everything
works from the terminal:

```sh
make build   # universal (arm64 + x86_64) release app at build/NerdStats.app
make run     # build, then launch (restarting any running copy)
make test    # unit tests; no special hardware needed
make dump    # print every reading once to the terminal, handy for checking sensors
make debug   # faster debug build of the app bundle
make clean
```

`make build` runs [`scripts/build-app.sh`](scripts/build-app.sh), which builds the
SwiftPM product for both architectures and wraps it in an `.app` bundle with
[`Resources/Info.plist`](Resources/Info.plist). The bundle is ad-hoc signed so it can run
locally; Developer ID signing and notarization are not set up yet.

To open the code in Xcode, open `Package.swift`.

## Architecture

```
Sources/
  CNerdStatsPrivate/   C declarations for private IOKit APIs (HID sensors) and the SMC struct
  NerdStatsCore/       All data collection and interpretation; no UI
    LowLevel/          sysctl, IORegistry, SMC and HID sensor access
    Sampling/          One sampler per subsystem + SnapshotSampler that combines them
    Models/            Plain value types the samplers return
    Math/              Pure logic: CPU tick deltas, counter rates, battery math,
                       SMC value decoding, status thresholds, sparkline history
    Formatting/        Units and human-readable formatting
  NerdStats/           The app
    App/               Entry point, StatsCoordinator (the sampling schedule), --dump
    Settings/          Preferences, launch at login, settings window
    Views/             SwiftUI dashboard, sections and small reusable components
Tests/NerdStatsCoreTests/
```

Data flows one way:

1. Each subsystem has a class conforming to `Sampler` (`CPUSampler`, `GPUSampler`,
   `MemorySampler`, `DiskSampler`, `NetworkSampler`, `PowerSampler`, `SensorSampler`,
   `SystemInfoSampler`, plus `ProcessSampler` for top processes). Samplers keep whatever
   state they need between calls, such as previous counters for computing rates.
2. `SnapshotSampler` owns one of each and refreshes a requested subset into a
   `SystemSnapshot`.
3. `StatsCoordinator` runs a single timer on the chosen interval and calls
   `SnapshotSampler` on a background queue. While the dashboard is closed it samples only
   what the menu bar readout needs (for example CPU ticks and the processor temperature
   sensors) and updates only the menu bar label. Opening the dashboard triggers a full
   sample and keeps everything refreshing until it closes.
4. SwiftUI views read the published snapshot and history; they never touch system APIs.

Logic that can be tested without hardware (tick deltas, rates, battery parsing, SMC
decoding, formatting, status thresholds) lives in `Math/`, `Formatting/` and small
parser types such as `BatteryParser` and `GPUStatistics`, and is covered by the tests.

## Where the data comes from

| Data | Source | Public API? |
| --- | --- | --- |
| CPU usage | `host_processor_info` per-core tick counters | Yes |
| Load averages | `getloadavg` | Yes |
| Top processes | `proc_listallpids`, `proc_pidinfo`, `proc_pid_rusage` | Yes (libproc) |
| Memory, swap, pressure | `host_statistics64`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` | Yes |
| GPU | `IOAccelerator` → `PerformanceStatistics` in the IORegistry | Undocumented registry keys |
| Disk capacity | `URLResourceValues` volume keys | Yes |
| Disk throughput | `IOBlockStorageDriver` → `Statistics` in the IORegistry | Undocumented registry keys |
| Network | `NET_RT_IFLIST2` sysctl, `getifaddrs`, SystemConfiguration | Yes |
| Public IP | `https://api.ipify.org`, only when you click **Look up** | – |
| Battery | `AppleSmartBattery` in the IORegistry, `IOPSCopyExternalPowerAdapterDetails` | Undocumented registry keys |
| Temperatures (Apple Silicon) | `IOHIDEventSystemClient` temperature sensor services | **Private** |
| Temperatures (Intel), fans | `AppleSMC` IOKit user client | **Private** (undocumented interface) |

### Private interfaces and why the app is not sandboxed

macOS has no public API for temperatures or fan speeds. NerdStats uses the same
interfaces as other well-known monitors:

- **Apple Silicon temperatures** come from `IOHIDEventSystemClient`, a private function
  family exported by IOKit. The declarations live in
  [`NerdStatsPrivate.h`](Sources/CNerdStatsPrivate/include/NerdStatsPrivate.h).
- **Intel temperatures and all fan speeds** are read from the System Management
  Controller through the `AppleSMC` IOKit user client.
- **GPU, disk and battery statistics** come from IORegistry properties whose names are
  not documented and differ between vendors and macOS versions.

The App Sandbox blocks opening IOKit user clients such as `AppleSMC` and restricts
IORegistry and HID access, so NerdStats is distributed outside the Mac App Store and
is not sandboxed. It needs no root privileges and has no helper tool. Because these
interfaces are unofficial, any of them can change in a future macOS release; every
reading is optional and the UI shows "unavailable" rather than crashing.

Some limits are imposed by macOS itself:

- Without root, CPU and memory for processes owned by other users (such as system
  daemons) cannot be read, so top-process lists cover your own processes.
- macOS rounds network byte counters to 1 KiB for ordinary apps, so very light traffic
  shows as steps of about 1 KB/s.
- Which sensors exist depends on the Mac model. Run `make dump` to see what yours reports.

### Hardware coverage

The Apple Silicon paths have been run on an M1 MacBook Air. The Intel code paths (SMC
temperature keys, `fpe2` fan values, Intel/AMD GPU statistics keys, mAh-based battery
values) are compiled into the universal binary and covered by unit tests with recorded
values, but have not yet been run on real Intel hardware.

## Dependencies

None beyond Apple's SDK frameworks (SwiftUI, AppKit, IOKit, SystemConfiguration,
ServiceManagement).
