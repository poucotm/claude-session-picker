# claude-session-picker

A PowerShell tool that lists **only the Claude Code sessions started in the current folder** and resumes the one you pick. Command: `cs`.

The `claude -r` list sometimes leaves out older sessions or mixes in sessions from other directories.
`cs` shows every session created in the current folder, with no age limit, and opens the selected one with `claude -r <sessionId>`.

```
 Claude Code : 이 폴더의 세션 5개  ↑↓ 이동 · Enter 재개 · Esc 취소

  ❯ xcpu-ram-traceback
      3일 전 · 2026-10-20 23:21 · master · 1.3MB

    session-delete-ambiguity
      4일 전 · 2026-10-19 22:02 · master · 466.5KB
```

The menu text is in Korean. Each entry shows the session title, then a relative time ("3일 전" = 3 days ago), date, git branch, and session file size.

## Install

1. Download the latest zip from [Releases](https://github.com/poucotm/claude-session-picker/releases) and extract it.
2. Double-click `install-claude-session-picker.cmd`.
3. Open a new PowerShell window.

Or run the installer from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File install-claude-session-picker.ps1
```

What the installer does:

- Copies `claude-session-picker.ps1` to `%USERPROFILE%\.claude\scripts\`.
- If the effective execution policy is `Restricted` (or undefined), sets it to `RemoteSigned` for the `CurrentUser` scope only.
- Adds this line to your PowerShell profile (`$PROFILE`). If a `cs` function pointing elsewhere (or one under the old name `csp`) already exists, it is replaced.

  ```powershell
  function cs { & "$HOME\.claude\scripts\claude-session-picker.ps1" @args }
  ```

Running it again is safe. To update, run the installer from a newer release.
PowerShell 7 (`pwsh`) has its own profile, so run the installer from `pwsh` too if you use it.

## Usage

Run it in a project folder:

```powershell
cs
cs --model opus   # extra arguments are passed through to claude
```

| Key | Action |
|---|---|
| ↑ / ↓ | Move |
| Enter | Resume the selected session (`claude -r <id>`) |
| Esc / q | Cancel |

## How it works

Session files (jsonl) can grow to tens of MB, so they are never read in full.

1. Builds the project folder name by replacing every non-alphanumeric character in the current path with `-`, and looks in `~\.claude\projects\<folder>`.
2. Collects session IDs from the **file names** `<sessionId>.jsonl` in that folder.
3. Reads only the lines in `~\.claude\history.jsonl` whose `"project"` equals the current path, to get each session's last prompt and time.
   Because the folder-name encoding is lossy (`\`, spaces and `-` all become `-`), different paths can share a folder; this step keeps only sessions whose path matches exactly.
   `exit` and `/command` entries are ignored for the title and time.
4. Reads only the **last 64 KB** of each session jsonl to get the title (`/rename` name, else the auto-generated title) and the git branch. Falls back to the last prompt if there is no title.

Empty sessions with no user messages have no entry in `history.jsonl` and are not listed.

## Requirements

- Windows, PowerShell 5.1 or later
- [Claude Code](https://claude.com/claude-code) with `claude` on your PATH
- The menu uses ANSI color codes. It renders correctly in Windows Terminal; the legacy console window may show garbled characters.
