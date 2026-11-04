# set-repo.ps1 — 一条命令完成：建远程仓库 → 推送 → 打 tag
#
# 用法（三种，任选其一）：
#   1) 已经 gh auth login 过（最省事）
#      .\scripts\set-repo.ps1 -Name tracker-sweep -Private
#
#   2) 用 HTTPS + PAT（不改本机登录状态）
#      .\scripts\set-repo.ps1 -Name tracker-sweep -Token ghp_xxx -User <你的GitHub用户名>
#
#   3) 只想推到一个已存在的空仓库
#      .\scripts\set-repo.ps1 -Repo https://github.com/<你>/tracker-sweep.git
#
# 做完会打印 Codemagic 的下一步。

param(
    [string]$Name = "tracker-sweep",
    [string]$User = "",
    [string]$Token = "",
    [string]$Repo = "",
    [switch]$Private,
    [string]$Tag = "v1.0.0",
    [string]$Message = "TrackerSweep: iOS 反追踪扫描 App"
)

$ErrorActionPreference = "Continue"
function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

$GH = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $GH)) { $GH = (Get-Command gh -ErrorAction SilentlyContinue).Source }

$script:LastCode = 0
function Run([string[]]$argv, [switch]$AllowFail) {
    $out = & git @argv 2>&1 | ForEach-Object { "$_" }
    $script:LastCode = $LASTEXITCODE
    if ($script:LastCode -ne 0 -and -not $AllowFail) {
        Write-Host ($out -join "`n") -ForegroundColor DarkGray
        Die ("git " + ($argv -join " ") + " 失败（$script:LastCode）")
    }
    return , $out
}

# ---------- 定位仓库根 ----------
Set-Location (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path "codemagic.yaml")) { Die "不在 tracker-sweep 目录" }
Info "工作目录: $(Get-Location)"

# ---------- 本地提交 ----------
if (-not (Test-Path ".git")) {
    Run @("init") | Out-Null
    Ok "git init"
}
Run @("config", "user.name", "tracker-sweep") | Out-Null
Run @("config", "user.email", "dev@local") | Out-Null
Run @("checkout", "-B", "main") -AllowFail | Out-Null
Run @("add", "-A") | Out-Null

$st = Run @("status", "--porcelain")
if ($st -and ($st | Where-Object { $_.Trim() }).Count -gt 0) {
    Run @("commit", "-m", $Message) | Out-Null
    Ok "已提交 $(($st | Where-Object { $_.Trim() }).Count) 个变更"
} else {
    Info "无变更需要提交"
}

# ---------- 决定 remote ----------
$remoteUrl = $Repo

if (-not $remoteUrl) {
    if ($Token) {
        if (-not $User) { Die "用 -Token 时必须同时给 -User <你的GitHub用户名>" }
        $vis = if ($Private) { "private" } else { "public" }
        $body = @{ name = $Name; private = [bool]$Private; auto_init = $false } | ConvertTo-Json
        Info "调用 GitHub API 创建仓库 $User/$Name ($vis) …"
        try {
            $r = Invoke-RestMethod -Method Post -Uri "https://api.github.com/user/repos" `
                -Headers @{ Authorization = "token $Token"; Accept = "application/vnd.github+json"; "User-Agent" = "tracker-sweep" } `
                -Body $body -ContentType "application/json"
            Ok "仓库已创建: $($r.html_url)"
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match "already exists|422") { Warn "仓库可能已存在，继续尝试推送" }
            else { Die "创建仓库失败: $msg" }
        }
        $remoteUrl = "https://$Token@github.com/$User/$Name.git"
    }
    elseif ($GH -and (Test-Path $GH)) {
        & $GH auth status *> $null
        if ($LASTEXITCODE -ne 0) {
            Die @"
还没登录 GitHub。二选一：
   A) 运行   & '$GH' auth login --web    （浏览器点一下，30 秒）
   B) 带 token 重跑   .\scripts\set-repo.ps1 -Token ghp_xxx -User <用户名>
"@
        }
        $vis = if ($Private) { "--private" } else { "--public" }
        Info "用 gh 创建仓库 $Name ($vis)…"
        & $GH repo create $Name $vis --source . --remote origin --push 2>&1 | ForEach-Object { "$_" } | Write-Host
        if ($LASTEXITCODE -eq 0) {
            $remoteUrl = (& $GH repo view --json url -q .url) + ".git"
            Ok "已创建并推送: $remoteUrl"
        } else {
            Warn "gh 创建失败，尝试直接读现有 remote"
            $remoteUrl = (Run @("remote", "get-url", "origin") -AllowFail | Select-Object -First 1)
        }
    }
    else { Die "没有 gh，也没有 -Repo / -Token。用 -Repo https://github.com/<你>/<仓库>.git" }
}

# ---------- 设置 remote 并推送 ----------
$cur = Run @("remote", "get-url", "origin") -AllowFail
if ($script:LastCode -eq 0) {
    Run @("remote", "set-url", "origin", $remoteUrl) | Out-Null
} else {
    Run @("remote", "add", "origin", $remoteUrl) | Out-Null
}
Ok "remote → $($remoteUrl -replace '//[^@]+@', '//***@')"

Info "推送 main …"
Run @("push", "-u", "origin", "main", "--force") -AllowFail | Out-Null
if ($script:LastCode -ne 0) { Die "推送失败（检查 token 权限 / 仓库是否为空）" }
Ok "分支 main 已推送"

# ---------- 打 tag ----------
$tags = Run @("tag", "--list", $Tag)
if ($tags -and $tags.Count -gt 0) {
    Warn "本地已有 tag $Tag，跳过创建（要改版本就换 -Tag v1.0.1）"
} else {
    Run @("tag", "-a", $Tag, "-m", "release $Tag") | Out-Null
    Ok "已创建 tag $Tag"
}
Run @("push", "origin", $Tag, "--force") | Out-Null
Ok "tag $Tag 已推送 → 会触发 TestFlight 构建"

Write-Host ""
Write-Host "下一步（Web 操作，只能你本人完成）：" -ForegroundColor Cyan
Write-Host "  1) https://codemagic.io → Sign up with GitHub → Add application → 选 $Name → 类型 Other"
Write-Host "  2) Teams → Integrations → App Store Connect → Name 填 ASC_KEY，粘 Issuer ID / Key ID / .p8"
Write-Host "  3) Apple 后台建 App ID + App 记录（见 SIGNING.md §1）"
Write-Host "  4) Codemagic 里 Start new build → 选 iOS TestFlight（tag 已推，也会自动跑）"
