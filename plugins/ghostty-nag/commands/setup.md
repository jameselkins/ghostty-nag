---
description: Configure Claude Code and Ghostty so the Dock-bounce nag actually fires
---

Installing this plugin wires the hook, but the hook alone does nothing: two
settings outside the plugin's reach control whether a BEL is ever emitted and
whether Ghostty reacts to it. Patch both, then report what changed.

Do not guess at the current state. Read each file before editing it, and make
the smallest edit that satisfies the requirement.

## 1. Claude Code notification channel

Read `~/.claude/settings.json` and ensure the top-level key
`"preferredNotifChannel"` is set to `"iterm2_with_bell"`.

Why this exact value: the channel decides what gets written to the tty, and
Ghostty's Dock bounce is BEL-triggered only.

- `auto` (the default) resolves by `TERM_PROGRAM` and picks the `ghostty`
  channel on Ghostty.
- `ghostty` emits OSC 777 and **never** emits BEL, so the Dock never bounces.
  It is also broken on Ghostty in practice (Claude Code issue #19979, closed as
  not planned, with `iterm2` given as the workaround). On `auto` you get
  nothing at all.
- `terminal_bell` emits BEL only: bounce, but no notification banner.
- `iterm2_with_bell` emits OSC 9 (Ghostty implements it, so you get the banner)
  **plus** BEL. This is the only value that gets both.

Preserve the rest of the file exactly, including key order and formatting. If
the key is already `iterm2_with_bell`, say so and change nothing.

No restart is needed: settings.json is re-read per notification.

## 2. Ghostty bell features

Find the Ghostty config. Check these in order and use the first that exists:

1. `~/Library/Application Support/com.mitchellh.ghostty/config`
2. `~/.config/ghostty/config`

If neither exists, create the first one.

The default `bell-features` is
`no-system,no-audio,attention,title,no-border`. The two that matter:

- `attention` drives the Dock bounce. On by default, and it only fires while
  Ghostty is unfocused, which is exactly what we want. **Required.**
- `system` plays the macOS alert sound. Off by default. Add it only if the user
  wants an audible ping as well.

Read the existing `bell-features` line if there is one and merge into it rather
than overwriting: keep any features the user already set, drop any `no-` prefix
on the features being enabled, and do not silently turn off something they had
on. If there is no `bell-features` line, append:

```
bell-features = system,attention,title
```

Ask the user whether they want the alert sound before including `system`.

This needs Ghostty >= 1.3. Check with `ghostty --version` and warn if it is
older. A config reload is required: tell the user to hit `Cmd+Shift+,`.

## 3. Report

Summarize in a few lines: which files you touched, what each value is now, and
the two manual steps if any remain (Ghostty reload, Ghostty upgrade). Then tell
them how to test it: run any command, switch to another app before it finishes,
and watch the Dock.
