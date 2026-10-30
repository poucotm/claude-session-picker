# claude-session-picker.ps1 을 ~\.claude\scripts 에 복사하고, PowerShell 프로필에 cs 함수를 등록한다.
# 실행: powershell -ExecutionPolicy Bypass -File install-claude-session-picker.ps1   (claude-session-picker.ps1 과 같은 폴더에서)

$name = 'claude-session-picker.ps1'
$dest = Join-Path $HOME '.claude\scripts'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $dest -Force
Unblock-File -LiteralPath (Join-Path $dest $name)  # 인터넷에서 받은 파일 표시 제거 (RemoteSigned 에서 막히지 않게)
Write-Host "복사: $dest\$name"

# 실행 정책: 이번 실행용 Bypass(Process)를 빼고 실제 적용되는 정책이 Restricted/미지정이면 RemoteSigned 로 바꾼다
$policy = (Get-ExecutionPolicy -List | Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
    Select-Object -First 1).ExecutionPolicy
if (-not $policy -or $policy -eq 'Restricted') {
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
    Write-Host "실행 정책: CurrentUser 를 RemoteSigned 로 변경"
}

# 프로필 등록 ($HOME 은 실행할 때 풀리도록 작은따옴표로 둔다)
$line = 'function cs { & "$HOME\.claude\scripts\claude-session-picker.ps1" @args }'
if (-not (Test-Path -LiteralPath $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
# 프로필의 기존 인코딩(UTF-8 BOM 이면 그대로, 아니면 시스템 기본)을 유지해서 다시 쓴다
$bytes = [IO.File]::ReadAllBytes($PROFILE)
$enc = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { New-Object Text.UTF8Encoding $true } else { [Text.Encoding]::Default }
$text = [IO.File]::ReadAllText($PROFILE, $enc)
$pattern = '(?m)^[ \t]*function[ \t]+csp?[ \t][^\r\n]*'  # 예전 이름 csp 도 cs 로 바꾼다
$old = [regex]::Match($text, $pattern)
if (-not $old.Success) {
    if ($text -and -not $text.EndsWith("`n")) { $text += "`r`n" }
    [IO.File]::WriteAllText($PROFILE, $text + $line + "`r`n", $enc)
    Write-Host "프로필 등록: $PROFILE"
}
elseif ($old.Value.Trim() -ne $line) {
    [IO.File]::WriteAllText($PROFILE, [regex]::Replace($text, $pattern, $line.Replace('$', '$$')), $enc)
    Write-Host "프로필 갱신: $PROFILE"
    Write-Host "  이전: $($old.Value.Trim())"
}
else { Write-Host "프로필: 이미 등록되어 있음" }

Write-Host "완료. 새 PowerShell 창에서 프로젝트 폴더로 이동한 뒤 cs 를 실행하세요."
