# Changelog

## 0.4.0 (October 2026)

- Clippo is now Kurenai (紅, "crimson"). Two other clipboard apps on the Mac App Store were already called Clippo, so it was time. Same app, same shortcuts.
- New icon, and a new menu bar icon.
- Your history, lists and settings move over on their own. If you update from inside the app, it renames itself to Kurenai.app and keeps its Accessibility permission.

## 0.3.6 (October 2026)

- Only one Clippo runs at a time. A second copy, for example one started from Downloads while the installed one is running, now steps aside instead of recording every copy twice.
- The "Encrypt history" setting is read reliably even when it was set from Terminal.

## 0.3.5 (October 2026)

- Fixed: Return and Cmd+1 to Cmd+9 in the history window could paste a different item than the highlighted one, if you had copied something new since the window was last open.

## 0.3.4 (October 2026)

- Remote desktop: Windows App and similar clients only accept Ctrl and Shift from a real keyboard, so Clippo can't press Ctrl+V for you there. Now it puts the item on the clipboard, switches back to the session and shows "Press Ctrl+V". The paste queue works the same way: Cmd+V loads the next item, Ctrl+V pastes it. Shift+Cmd+C waits for your own Ctrl+C and splits what you copied into lines.

## 0.3.3 (October 2026)

- Pasting into Windows App and other remote desktop clients works now. Clippo presses Ctrl the way a real keyboard does, so the remote side gets Ctrl+V instead of a plain V.

## 0.3.2 (October 2026)

- Update from inside the app: Clippo menu > Check for Updates. It downloads the new version, checks it's signed by the same developer, replaces itself and restarts.
- New menu bar icon, and the last three copies right in the menu.
- Works over remote desktop (Windows App, Parallels Client, Citrix, Horizon): pastes with Ctrl+V and waits for the clipboard to sync.
- Editing a line in a saved list no longer pastes it and closes the window.
- Lighter on the battery: the clipboard is checked less often and macOS can group those checks with other timers.

## 0.3.1 (October 2026)

- Dates in the history list were formatted in Russian even in the English interface.
- The selected tab in the history window was hard to read.
- Clearer wording across the interface.
- `Clippo -ClippoDemo` for screenshots with sample data.

## 0.3 (October 2026)

First public release.

- History with search, text and images (⌘;), paste by number with ⌘1 to ⌘9.
- Saved lists (⌘I).
- Paste queue (⌘'), ⇧⌘C splits a column into lines.
- Skips passwords from password managers, per-app exclusions, encrypted history.
- Custom shortcuts, English, Russian and Chinese.
