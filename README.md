# GrimTactics (working title)

One hero against a boss on hex tiles, turn based, with a few mechanics from
the Dark Souls board game. See PLAN.md.

- `play.bat` starts it.
- Tests: `godot --headless --path . -- --smoke`
- Screenshot: `godot --path . -- --shot out.png [frames] [--auto N] [--dodge]`
- Phone: `build_apk.bat` makes `build/GrimTactics.apk`; `build_apk.bat install`
  also installs it on a phone plugged in by USB (USB debugging on).
