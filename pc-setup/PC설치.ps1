# PC 에서 Claude Code 를 옵시디언 보관함(ClaudeVault)에 직접 연결한다. 한 번만 실행하면 된다.
#
#   실행: PowerShell 을 열고
#     powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\PC설치.ps1"
#
# 하는 일
#   1. Claude Code 설치 (이미 있으면 건너뜀)
#   2. Git for Windows 설치 (없으면 winget 으로. Claude Code 가 Bash 를 쓰는 데 필요)
#   3. 보관함 CLAUDE.md 에 "블로그 글은 네이버블로그 폴더에 저장하고 옵시디언에서 열기" 규칙 추가
#   4. 바탕 화면에 "Claude 블로그" 바로가기 (보관함에서 Claude Code 를 연다)
param(
    [string]$Vault = "$env:USERPROFILE\OneDrive\Documents\ClaudeVault"
)
$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n▶ $msg" -ForegroundColor Cyan }

# ---------- 보관함 ----------
while (-not (Test-Path -LiteralPath $Vault)) {
    Write-Host "옵시디언 보관함을 찾을 수 없습니다: $Vault" -ForegroundColor Yellow
    $Vault = Read-Host "보관함 폴더 경로를 붙여 넣으세요 (ClaudeVault 폴더)"
    $Vault = $Vault.Trim('"', ' ')
}
$BlogDir = Join-Path $Vault '네이버블로그'
if (-not (Test-Path -LiteralPath $BlogDir)) { New-Item -ItemType Directory -Path $BlogDir | Out-Null }

# ---------- 1. Claude Code ----------
Step 'Claude Code 설치 확인'
$localBin = "$env:USERPROFILE\.local\bin"
if (-not (Get-Command claude -ErrorAction SilentlyContinue) -and -not (Test-Path "$localBin\claude.exe")) {
    Write-Host '설치합니다...'
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
}
if ($env:Path -notlike "*$localBin*") { $env:Path = "$localBin;$env:Path" }
$claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $claude) { throw 'Claude Code 설치를 확인하지 못했습니다. 새 PowerShell 창에서 다시 실행해 보세요.' }
Write-Host "Claude Code: $(& $claude --version)"

# ---------- 2. Git ----------
Step 'Git 설치 확인'
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Git: $(git --version)"
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
} else {
    Write-Host 'winget 이 없어 Git 을 자동으로 설치하지 못했습니다. https://git-scm.com 에서 설치하세요. (없어도 Claude Code 는 동작합니다)' -ForegroundColor Yellow
}

# ---------- 3. 보관함 CLAUDE.md ----------
Step '보관함 CLAUDE.md 에 블로그 규칙 추가'
$begin = '<!-- 네이버블로그-자동화 시작 -->'
$end   = '<!-- 네이버블로그-자동화 끝 -->'
$rules = @"
$begin
## 블로그 글을 써 달라고 하면

1. ``네이버블로그\YYYY-MM-DD-제목.md`` 로 저장한다 (UTF-8, 오늘 날짜).
   파일 이름에 ``\ / : * ? " < > |`` 는 쓰지 않는다.
2. 형식:

   ``````markdown
   # 제목

   본문. 네이버 블로그에 그대로 옮겨지므로 ## 소제목, **굵게**, 목록, 표 정도만 쓴다.
   이미지 문법이나 HTML 은 쓰지 않는다.

   태그: #태그1 #태그2 #태그3
   ``````

3. 저장한 뒤 PowerShell 로 옵시디언에서 그 파일을 연다:
   ``Start-Process ("obsidian://open?path=" + [uri]::EscapeDataString((Resolve-Path -LiteralPath '<저장한 파일>').Path))``
4. 이어서 네이버 블로그 글쓰기 창을 연다:
   ``Start-Process "https://blog.naver.com/GoBlogWrite.naver"``
5. 사용자에게 알린다: "네이버포스팅.ahk 가 방금 저장한 글을 자동으로 잡습니다.
   제목칸 클릭 → F9, 본문 클릭 → F10. (다른 글이 잡히면 Ctrl+Alt+9)"

고쳐 달라고 하면 같은 파일을 고친다.
$end
"@
$claudeMd = Join-Path $Vault 'CLAUDE.md'
$utf8 = New-Object Text.UTF8Encoding $false
$old = if (Test-Path -LiteralPath $claudeMd) { [IO.File]::ReadAllText($claudeMd, $utf8) } else { '' }
$pattern = [regex]::Escape($begin) + '[\s\S]*?' + [regex]::Escape($end)
if ($old -match $pattern) {
    $new = [regex]::Replace($old, $pattern, { param($m) $rules })     # 예전 규칙만 바꿔 끼운다
} else {
    $new = ($old.TrimEnd() + "`r`n`r`n" + $rules).TrimStart()        # 기존 내용은 그대로 둔다
}
[IO.File]::WriteAllText($claudeMd, $new.Replace("`r`n", "`n").Replace("`n", "`r`n"), $utf8)
Write-Host "저장: $claudeMd"

# ---------- 4. 바로가기 ----------
Step '바탕 화면 바로가기 만들기'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Claude 블로그.lnk'))
$lnk.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments        = "-NoExit -NoLogo -Command `"Set-Location -LiteralPath '$Vault'; & '$claude'`""
$lnk.WorkingDirectory = $Vault
$lnk.IconLocation     = "$claude,0"
$lnk.Save()
Write-Host "바로가기: $(Join-Path $desktop 'Claude 블로그.lnk')"

Write-Host "`n완료! 바탕 화면의 'Claude 블로그' 를 열고 (처음엔 로그인)" -ForegroundColor Green
Write-Host "'○○ 주제로 블로그 글 써줘' 라고 하면 네이버블로그 폴더에 저장되고 옵시디언에서 열립니다." -ForegroundColor Green
