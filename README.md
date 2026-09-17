# NerdStats

**See how your Mac is really doing, right from the menu bar.**

[![Latest release](https://img.shields.io/github/v/release/tsvillain/nerdstats?label=download)](https://github.com/tsvillain/nerdstats/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)

**[Download NerdStats](https://github.com/tsvillain/nerdstats/releases/latest)** · [Website](https://tsvillain.github.io/nerdstats/)

Free for macOS 13 Ventura or later, on Apple Silicon and Intel Macs.

<!-- Screenshot placeholder: add a dashboard screenshot here once one is available. -->

## Why NerdStats

Is your Mac slow because something is hogging the CPU, running low on memory, or just
getting hot? NerdStats answers at a glance. It sits quietly in the menu bar, gives you a
plain-language verdict (**Normal**, **Busy** or **Hot**), and when you want the details,
flip the **Nerd** switch to see every number behind it.

## Highlights

- **Your stats, your menu bar.** Show CPU, GPU, Memory, SSD and Battery as separate menu
  bar items, in any combination. Click one to jump straight to that section.
- **Clear answers for everyone.** Usage, memory pressure, free space, network speed,
  battery health and temperatures, explained in plain language.
- **Nerd mode when you want depth.** Per-core CPU bars and load averages, the apps using
  the most CPU and memory, live network connections per app, every temperature sensor and
  fan, and detailed battery health (cycle count, capacity, voltage, adapter wattage).
- **Stop runaway apps.** Quit or Force Quit your own processes straight from the dashboard.
- **Made for every modern Mac.** One app for Apple Silicon and Intel.
- **Lightweight.** While the dashboard is closed, NerdStats only reads what your menu bar
  items show. Choose how often it refreshes: every 1, 2, 5 or 10 seconds.
- **Honest readings.** If your Mac doesn't report something, NerdStats says so instead of
  guessing.
- **Free.** No accounts, no subscriptions.

## Install

1. [Download](https://github.com/tsvillain/nerdstats/releases/latest) the latest
   `NerdStats-<version>.dmg`.
2. Open it and drag **NerdStats** into **Applications**.
3. Open NerdStats from Applications. It appears in the menu bar, not the Dock.

**First launch only:** macOS will say it can't verify NerdStats. That's expected, and you
only need to allow it once. Click **Done**, open **System Settings > Privacy & Security**,
scroll down and click **Open Anyway** next to the NerdStats message, then confirm. (Prefer
the terminal? `xattr -dr com.apple.quarantine /Applications/NerdStats.app` does the same.)

NerdStats starts automatically when you log in; you can turn that off in Settings.

## Privacy

NerdStats runs entirely on your Mac. There's no telemetry, no analytics and no account.
The only time it contacts the internet is when you click **Look up** to see your public IP
address.

## FAQ

**Why does macOS show a security warning?**
NerdStats isn't signed with a paid Apple Developer ID or notarized by Apple yet, so macOS
asks you to confirm the first launch. Follow the one-time **Open Anyway** step above.

**Why isn't it on the Mac App Store?**
macOS has no public way to read temperatures and fan speeds. NerdStats uses the same
system interfaces as other well-known Mac monitors, and the App Store sandbox blocks them.
It doesn't need an admin password or install any helper tools.

**Will it slow down my Mac?**
It's designed not to. With the dashboard closed it reads only what your menu bar items
display, and detailed data such as network connections is collected only while you're
looking at it. You can also lower the refresh rate in Settings.

**Which Macs does it support?**
Any Mac running macOS 13 Ventura or later, Apple Silicon or Intel. Available sensors vary
by model; the battery section is hidden on Macs without a battery.

---

Building from source? See [CONTRIBUTING.md](CONTRIBUTING.md).
