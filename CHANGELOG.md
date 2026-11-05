# Changelog

## 0.5.0 (November 2026)

- Typed in the wrong layout? Kurenai fixes it as you type, like Punto Switcher. "ghbdtn" turns into "привет" by the fourth letter and the layout switches, so you just keep typing. Words it can't judge mid-word are checked again at the Space.
- Tap the right Shift twice to retype the selection or the last word in the other layout yourself, slang and names included. With no text it just switches the layout.
- Fixed one by mistake? Tap the right Shift twice right away to get it back. Undo the same word a few times and Kurenai leaves it alone from then on.
- The mapping comes from your own layouts and keyboard (ABC, Russian, Russian PC, Ukrainian and others, ISO or ANSI), not from a built-in table.
- If a layout's language has no spelling dictionary in macOS, Kurenai offers to download a free one.
- Off in terminals, code editors, remote desktop and password fields. Both features can be turned off in Settings.
- Security: the data folder is readable only by you, the encryption key file is created private from the start, and updates are checked more strictly before they replace the app.

## 0.4.0 (October 2026)

- The app is now called Kurenai (紅, "crimson"). Same app, same shortcuts.
- New icon, and a new menu bar icon.
- Your history, lists and settings move over on their own. If you update from inside the app, it renames itself to Kurenai.app and keeps its Accessibility permission.

## 0.3.6 (October 2026)

- Only one Kurenai runs at a time. A second copy, for example one started from Downloads while the installed one is running, now steps aside instead of recording every copy twice.
- The "Encrypt history" setting is read reliably even when it was set from Terminal.

## 0.3.5 (October 2026)

- Fixed: Return and Cmd+1 to Cmd+9 in the history window could paste a different item than the highlighted one, if you had copied something new since the window was last open.

## 0.3.4 (October 2026)

- Remote desktop: Windows App and similar clients only accept Ctrl and Shift from a real keyboard, so Kurenai can't press Ctrl+V for you there. Now it puts the item on the clipboard, switches back to the session and shows "Press Ctrl+V". The paste queue works the same way: Cmd+V loads the next item, Ctrl+V pastes it. Shift+Cmd+C waits for your own Ctrl+C and splits what you copied into lines.

## 0.3.3 (October 2026)

- Pasting into Windows App and other remote desktop clients works now. Kurenai presses Ctrl the way a real keyboard does, so the remote side gets Ctrl+V instead of a plain V.

## 0.3.2 (October 2026)

- Update from inside the app: Kurenai menu > Check for Updates. It downloads the new version, checks it's signed by the same developer, replaces itself and restarts.
- New menu bar icon, and the last three copies right in the menu.
- Works over remote desktop (Windows App, Parallels Client, Citrix, Horizon): pastes with Ctrl+V and waits for the clipboard to sync.
- Editing a line in a saved list no longer pastes it and closes the window.
- Lighter on the battery: the clipboard is checked less often and macOS can group those checks with other timers.

## 0.3.1 (October 2026)

- Dates in the history list were formatted in Russian even in the English interface.
- The selected tab in the history window was hard to read.
- Clearer wording across the interface.
- `Kurenai -KurenaiDemo` for screenshots with sample data.

## 0.3 (October 2026)

First public release.

- History with search, text and images (⌘;), paste by number with ⌘1 to ⌘9.
- Saved lists (⌘I).
- Paste queue (⌘'), ⇧⌘C splits a column into lines.
- Skips passwords from password managers, per-app exclusions, encrypted history.
- Custom shortcuts, English, Russian and Chinese.
