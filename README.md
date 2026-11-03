# Daily Poms

A tiny, private iOS app for tracking focus chunks on screen and counting poms (pomodoros) per day.
Built as the sibling app to `DailyMusts`: no accounts, no cloud, no ads.

## What it does

- **On-screen chunk timer.** Track 15, 25, 45, or 60-minute focus chunks (plus Short and Long Breaks) with a large circular countdown ring that can keep your screen awake on your desk.
- **Wall-clock accuracy.** Locking your iPhone or switching apps never loses time; an optional local notification chimes when a chunk finishes.
- **Daily pom count & goal.** Watch today's poms fill up toward your daily target, log an early or past chunk with one tap, and tag chunks with optional labels.
- **History tab.** Current streak, best streak, goal days (last 60 days), last-7-days focus totals, and a day-by-day record of the last 60 days.
- **Widgets.** Home Screen small (progress ring + streak) and medium (today's poms), plus Lock Screen circular and rectangular.
- **Reminders & Export.** Optional morning nudge and evening check-in (stays quiet once today's goal is met), CSV export, and full data erase.

## Streak rules

- Reaching your daily pom target (default 4) marks the day as won.
- Today never breaks a streak while the day is still in progress.

## Build & Run

1. Run `xcodegen generate` to generate `DailyPoms.xcodeproj`.
2. Open `DailyPoms.xcodeproj` in Xcode, select your iPhone or Simulator, and press Run (▶).
