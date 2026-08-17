# ghostty-nag

Claude Code finishes, you're in another window, and you don't notice for eleven
minutes. Ghostty bounces its Dock icon exactly once and gives up.

This plugin keeps it bouncing until you come back.

macOS + [Ghostty](https://ghostty.org) >= 1.3 only.

## Install

```
/plugin marketplace add jameselkins/ghostty-nag
/plugin install ghostty-nag@elkins-tools
/ghostty-nag:setup
```

The third step is not optional. Installing the plugin wires the hook, but two
settings live outside a plugin's reach and nothing bounces without them:
`preferredNotifChannel` in `~/.claude/settings.json`, and `bell-features` in
Ghostty's own config. `/ghostty-nag:setup` reads both, patches what's missing,
and leaves the rest alone.

## When it nags

| Hook event | Fires when |
| --- | --- |
| `Stop` | Claude finished the turn |
| `Notification` (`permission_prompt`, `agent_needs_input`) | Claude is blocked waiting on you |
| `StopFailure` | The turn died on an API error |

The permission-prompt case is the one that earns its keep. That's Claude sitting
idle waiting for an approval you don't know it wants.

## Config

Set at install time, changeable later with `/plugin`:

| Option | Default | What it does |
| --- | --- | --- |
| Seconds between bells | `10` | One Dock bounce per bell |
| Give up after | `300` | Stop nagging eventually |
| Terminal bundle ID | `com.mitchellh.ghostty` | Only change for a fork or nightly |

## Why a loop instead of a config flag

Ghostty's `attention` bell feature calls macOS `requestUserAttention` with
`NSInformationalRequest`, which bounces the icon once. The repeating variant,
`NSCriticalRequest`, isn't exposed by any Ghostty option, and no external
process can request attention on another app's behalf. Re-sending BEL on an
interval is the only route.

The loop exits the moment Ghostty regains focus, so it never nags at a terminal
you're already looking at. Focus detection uses `lsappinfo`, which needs no
Accessibility permission (`osascript`/System Events does).

## Two things that will waste your afternoon

**`preferredNotifChannel` decides whether a BEL is ever written to the tty.**
The default `auto` resolves to the `ghostty` channel, which emits OSC 777 and
never emits BEL, so `bell-features` never fires. It's also just broken on
Ghostty ([#19979](https://github.com/anthropics/claude-code/issues/19979),
closed as not planned, workaround is `iterm2`). `iterm2_with_bell` is the only
value that gets you both the banner and the bounce.

**Hook processes have no controlling terminal.** `ps -o tty= -p $$` returns
`??` and writing to `/dev/tty` fails with "Device not configured" even from a
foreground hook. A failed redirect doesn't abort the script, so this fails
silently with exit code 0. The script walks up the process chain via
`ps -o ppid=` until it finds a real tty name, then writes to `/dev/<name>`
directly. The `claude` process itself owns the pty.

## License

MIT
