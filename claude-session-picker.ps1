# 현재 폴더에서 시작한 Claude Code 세션만 나열하고, 고른 세션을 claude -r 로 재개한다.
# 사용법: csp [claude에 넘길 추가 인자...]   (install-claude-session-picker.ps1 로 프로필에 등록)
#   ↑↓ 이동, Enter 재개, Esc/q 취소

$cwd = (Get-Location).ProviderPath
$claudeDir = Join-Path $env:USERPROFILE '.claude'
$dir = Join-Path $claudeDir ('projects\' + ($cwd -replace '[^a-zA-Z0-9]', '-'))
$history = Join-Path $claudeDir 'history.jsonl'
$ko = (Get-Culture).Name -like 'ko*'  # Windows 지역 형식이 한국어면 한글, 아니면 영어로 표시

# 1) projects 하위 폴더의 jsonl 파일 이름 = 재개 가능한 세션ID
$ids = @{}
if (Test-Path -LiteralPath $dir) {
    Get-ChildItem -LiteralPath $dir -Filter *.jsonl -File | ForEach-Object { $ids[$_.BaseName] = $true }
}

# 2) history.jsonl 에서 이 폴더 경로의 줄만 골라 세션별 마지막 프롬프트를 얻는다
$sessions = @{}
if ($ids.Count -gt 0 -and (Test-Path -LiteralPath $history)) {
    $key = '"project":"' + $cwd.Replace('\', '\\') + '"'
    foreach ($m in Select-String -LiteralPath $history -SimpleMatch -Pattern $key -Encoding UTF8) {
        $h = $m.Line | ConvertFrom-Json
        if ($h.project -ne $cwd -or -not $ids.ContainsKey($h.sessionId)) { continue }
        $s = $sessions[$h.sessionId]
        if ($null -eq $s) {
            $s = [pscustomobject]@{ Id = $h.sessionId; Time = 0; Title = ''; AnyTime = 0; AnyTitle = '' }
            $sessions[$h.sessionId] = $s
        }
        $prompt = ($h.display -replace '\s+', ' ').Trim()
        if ($h.timestamp -ge $s.AnyTime) { $s.AnyTime = $h.timestamp; $s.AnyTitle = $prompt }
        # exit 나 /명령 은 세션 내용을 알려주지 않으므로, 다른 프롬프트가 있으면 그쪽의 내용과 시각을 쓴다
        if ($prompt -notmatch '^(/|exit$|quit$)' -and $h.timestamp -ge $s.Time) { $s.Time = $h.timestamp; $s.Title = $prompt }
    }
}

# 3) 제목: 세션 jsonl 끝 64KB 에서 마지막 customTitle(/rename) > aiTitle, 없으면 프롬프트
foreach ($s in $sessions.Values) {
    if (-not $s.Title) { $s.Time = $s.AnyTime; $s.Title = $s.AnyTitle }

    $fs = [IO.File]::OpenRead((Join-Path $dir "$($s.Id).jsonl"))
    try {
        $n = [int][Math]::Min(65536, $fs.Length)
        [void]$fs.Seek(-$n, 'End')
        $buf = New-Object byte[] $n
        [void]$fs.Read($buf, 0, $n)
        $tail = [Text.Encoding]::UTF8.GetString($buf)
        $s | Add-Member Size $fs.Length
    }
    finally { $fs.Close() }

    foreach ($name in 'customTitle', 'aiTitle') {
        $m = [regex]::Matches($tail, '"' + $name + '":"((?:[^"\\]|\\.)*)"')
        if ($m.Count -gt 0) { $s.Title = [regex]::Unescape($m[$m.Count - 1].Groups[1].Value); break }
    }
    $m = [regex]::Matches($tail, '"gitBranch":"((?:[^"\\]|\\.)*)"')
    $s | Add-Member Branch $(if ($m.Count -gt 0) { [regex]::Unescape($m[$m.Count - 1].Groups[1].Value) })
}

if ($sessions.Count -eq 0) {
    Write-Host $(if ($ko) { "이 폴더($cwd)에서 만든 세션이 없습니다." } else { "No sessions were created in this folder ($cwd)." })
    return
}

$list = @($sessions.Values | Sort-Object Time -Descending)

# 한글 등 전각 문자는 2칸으로 계산해서 한 줄 폭에 맞게 자른다
function Format-Width([string]$text, [int]$width) {
    $sb = New-Object Text.StringBuilder
    $w = 0
    foreach ($c in $text.ToCharArray()) {
        $u = [int]$c
        $cw = if (($u -ge 0x1100 -and $u -le 0x115F) -or ($u -ge 0x2E80 -and $u -le 0xA4CF) -or ($u -ge 0xAC00 -and $u -le 0xD7A3) -or
                  ($u -ge 0xF900 -and $u -le 0xFAFF) -or ($u -ge 0xFE30 -and $u -le 0xFE4F) -or ($u -ge 0xFF00 -and $u -le 0xFF60) -or
                  ($u -ge 0xFFE0 -and $u -le 0xFFE6)) { 2 } else { 1 }
        if ($w + $cw -gt $width) { break }
        [void]$sb.Append($c); $w += $cw
    }
    $sb.ToString() + (' ' * ($width - $w))
}

# 세션 정보 줄: "2주 전 · 2026-10-09 19:52 · HEAD · 651.8KB" (영어: "2 weeks ago · ...")
function Format-Info($s) {
    $t = [DateTimeOffset]::FromUnixTimeMilliseconds($s.Time).LocalDateTime
    $d = (Get-Date) - $t
    $n, $unit = if ($d.TotalHours -lt 1) { [Math]::Floor($d.TotalMinutes), 0 }
                elseif ($d.TotalDays -lt 1) { [Math]::Floor($d.TotalHours), 1 }
                elseif ($d.TotalDays -lt 7) { [Math]::Floor($d.TotalDays), 2 }
                elseif ($d.TotalDays -lt 30) { [Math]::Floor($d.TotalDays / 7), 3 }
                elseif ($d.TotalDays -lt 365) { [Math]::Floor($d.TotalDays / 30), 4 }
                else { [Math]::Floor($d.TotalDays / 365), 5 }
    $ago = if ($d.TotalMinutes -lt 1) { $(if ($ko) { '방금 전' } else { 'just now' }) }
           elseif ($ko) { "$n$(('분', '시간', '일', '주', '개월', '년')[$unit]) 전" }
           else { "$n $(('minute', 'hour', 'day', 'week', 'month', 'year')[$unit])$(if ($n -ne 1) { 's' }) ago" }
    $size = if ($s.Size -lt 1MB) { '{0:0.0}KB' -f ($s.Size / 1KB) } else { '{0:0.0}MB' -f ($s.Size / 1MB) }
    (@($ago, $t.ToString('yyyy-MM-dd HH:mm'), $s.Branch, $size) | Where-Object { $_ }) -join ' · '
}

# 4) 화살표 메뉴 (claude --resume 화면처럼 연보라색 + ❯ 로 선택 표시)
$e = [char]27
$accent = "$e[38;2;177;185;249m"; $dim = "$e[90m"; $cyan = "$e[96m"; $reset = "$e[0m"
$sel = 0; $top = 0
[Console]::CursorVisible = $false
try {
    while ($true) {
        $rows = [Math]::Max(1, [Math]::Floor(([Console]::WindowHeight - 2) / 3))  # 세션 하나 = 2줄 + 빈 줄
        $width = [Console]::WindowWidth - 1
        if ($sel -lt $top) { $top = $sel }
        if ($sel -ge $top + $rows) { $top = $sel - $rows + 1 }

        Clear-Host
        if ($ko) { Write-Host "$cyan Claude Code : 이 폴더의 세션 $($list.Count)개$reset$dim  ↑↓ 이동 · Enter 재개 · Esc 취소$reset" }
        else { Write-Host "$cyan Claude Code : $($list.Count) session(s) in this folder$reset$dim  ↑↓ move · Enter resume · Esc cancel$reset" }
        Write-Host ''
        for ($i = $top; $i -lt [Math]::Min($list.Count, $top + $rows); $i++) {
            if ($i -gt $top) { Write-Host '' }
            $title = Format-Width ($list[$i].Title -replace '\s+', ' ') ($width - 4)  # 들여쓰기 2칸 + "❯ "
            if ($i -eq $sel) { Write-Host "  $accent❯ $title$reset" }
            else { Write-Host "    $title" }
            Write-Host "      $dim$(Format-Info $list[$i])$reset"
        }

        switch ([Console]::ReadKey($true).Key) {
            'UpArrow'   { if ($sel -gt 0) { $sel-- } }
            'DownArrow' { if ($sel -lt $list.Count - 1) { $sel++ } }
            'Enter'     { $chosen = $list[$sel].Id }
            'Escape'    { return }
            'Q'         { return }
        }
        if ($chosen) { break }
    }
}
finally {
    [Console]::CursorVisible = $true
    Clear-Host
}

& claude -r $chosen @args
