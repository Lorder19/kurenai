# Contributing

Thanks for wanting to help. Kurenai is small on purpose, so before writing a big feature it's worth opening an issue to talk about it first.

## Building

```bash
./build.sh            # builds build/Kurenai.app
./build.sh install    # also copies it to /Applications and restarts it
```

You need the Xcode command line tools and macOS 14 or newer. See the README for the signing certificate trick that keeps Accessibility permission across rebuilds.

`Kurenai -KurenaiDemo history` (also `list`, `queue`, `settings`, `onboarding`) runs on sample data in a temp folder. Handy for screenshots and for poking at the UI without touching your own history.

## Code

- Swift, AppKit for windows and the menu bar, SwiftUI for what's inside the panels. No dependencies, please keep it that way.
- Interface strings are written in Russian and wrapped in `L("...")`. Translations live in `Resources/<lang>.lproj/Localizable.strings`. When you add a string, add it to every table.
- Anything that touches what gets stored deserves extra care. If you're not sure, ask.

## Translations

Adding a language is the easiest way to help. Copy `Resources/en.lproj` to your language code, translate the right-hand side of each line and add the code to `CFBundleLocalizations` in `build.sh`.

## Pull requests

Keep them focused on one thing and describe how you tested. Screenshots for UI changes are great.
