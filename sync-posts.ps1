# Claude 가 GitHub 저장소 posts/ 에 올린 블로그 글(.md)을 옵시디언 보관함으로 가져온다.
# 네이버포스팅.ahk 가 1분마다 숨겨서 실행한다. 직접 실행해도 된다.
#
# Claude 세션마다 브랜치 이름이 달라서 원격의 모든 브랜치를 훑는다.
# 같은 글이 여러 브랜치에 있으면 가장 최근에 커밋된 브랜치의 것을 쓴다.
# 새로 가져온 파일의 전체 경로를 -OutFile 에 한 줄씩 적는다 (오래된 것 → 최신 순).
# 실패하면 -OutFile 에 "ERROR<탭>이유" 한 줄만 적는다.
param(
    [Parameter(Mandatory)] [string]$RepoUrl,
    [Parameter(Mandatory)] [string]$RepoDir,
    [Parameter(Mandatory)] [string]$VaultDir,
    [Parameter(Mandatory)] [string]$OutFile
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$utf8 = New-Object Text.UTF8Encoding $false

function Invoke-Git {
    $out = & git -C $RepoDir -c core.quotepath=false @args
    if ($LASTEXITCODE) { throw "git $($args[0]) 실패 (코드 $LASTEXITCODE)" }
    $out
}

# 글 내용을 바이트 그대로 파일에 쓴다. (PowerShell 파이프를 거치면 인코딩이 바뀐다)
function Save-Blob($sha, $dest) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'git'
    $psi.Arguments = "-C `"$RepoDir`" cat-file blob $sha"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $fs = [IO.File]::Create($dest)
    try { $proc.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Close() }
    $proc.WaitForExit()
    if ($proc.ExitCode) { throw "글을 꺼내지 못했습니다: $dest" }
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git 이 설치되어 있지 않습니다 (https://git-scm.com 에서 설치)'
    }
    if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
        & git clone --no-checkout --quiet $RepoUrl $RepoDir
        if ($LASTEXITCODE) { throw "저장소를 받지 못했습니다: $RepoUrl" }
    }
    Invoke-Git fetch origin --prune --quiet

    # 경로 → 가장 최근 브랜치의 {sha, time}
    $latest = @{}
    foreach ($row in (Invoke-Git for-each-ref --sort=committerdate '--format=%(committerdate:unix) %(refname)' refs/remotes/origin)) {
        $time, $ref = $row -split ' ', 2
        if ($ref -like '*/HEAD') { continue }
        foreach ($line in (Invoke-Git ls-tree -r $ref -- posts)) {
            $meta, $path = $line -split "`t", 2
            if ($path -notlike '*.md') { continue }
            $latest[$path] = @{ sha = ($meta -split ' ')[2]; time = [long]$time }
        }
    }

    # 마지막으로 가져온 버전. 옵시디언에서 고쳤는지 알아보는 데 쓴다.
    $stateFile = Join-Path $RepoDir '.git\claude-synced.tsv'
    $state = @{}
    if (Test-Path -LiteralPath $stateFile) {
        foreach ($l in [IO.File]::ReadAllLines($stateFile, $utf8)) {
            $p, $s = $l -split "`t", 2
            if ($s) { $state[$p] = $s }
        }
    }

    $result = New-Object Collections.Generic.List[string]
    # 오래된 것부터 써야 마지막에 쓴 파일이 최신 글이 된다 (ahk 는 수정 시각으로 최신 글을 고른다)
    foreach ($path in ($latest.Keys | Sort-Object { $latest[$_].time }, { $_ })) {
        $sha = $latest[$path].sha
        if ($state[$path] -eq $sha) { continue }
        if (-not (Test-Path -LiteralPath $VaultDir)) {
            New-Item -ItemType Directory -Path $VaultDir | Out-Null
        }
        $name = Split-Path $path -Leaf
        $base = [IO.Path]::GetFileNameWithoutExtension($name)
        $dest = Join-Path $VaultDir $name
        if (Test-Path -LiteralPath $dest) {
            $local = Invoke-Git hash-object --no-filters -- $dest
            if (-not $state.ContainsKey($path)) {
                # 같은 이름의 다른 글이 이미 있으면 건드리지 않는다
                $dest = Join-Path $VaultDir "$base (Claude).md"
            } elseif ($local -ne $state[$path]) {
                # 옵시디언에서 고친 글은 덮어쓰지 않고 수정본을 옆에 둔다
                $dest = Join-Path $VaultDir "$base (Claude 수정본).md"
            }
        }
        Save-Blob $sha $dest
        $state[$path] = $sha
        $result.Add($dest)
    }

    [IO.File]::WriteAllLines($stateFile, [string[]]@($state.GetEnumerator() | ForEach-Object { "$($_.Key)`t$($_.Value)" }), $utf8)
    [IO.File]::WriteAllLines($OutFile, [string[]]@($result), $utf8)
} catch {
    [IO.File]::WriteAllText($OutFile, "ERROR`t" + $_.Exception.Message, $utf8)
}
