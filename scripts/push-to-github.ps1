# push-to-github.ps1 — Windows 上一键把 tracker-sweep 推到 GitHub
#
# 用法：
#   .\scripts\push-to-github.ps1 -Repo "https://github.com/<你>/tracker-sweep.git"
#   .\scripts\push-to-github.ps1 -Repo "git@github.com:<你>/tracker-sweep.git" -Branch main
#
# 注意：git 会把 "Switched to a new branch" 写到 stderr，
#       PowerShell 5.1 在 $ErrorActionPreference=Stop 下会把它当致命错误，
#       所以这里统一用 "捕获输出 + 检查 $LASTEXITCODE" 的方式调用外部命令。

param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Branch = "main",
    [string]$Message = "TrackerSweep: iOS 反追踪扫描 App",
    [switch]$Force
)

$ErrorActionPreference = "Continue"

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# 跑外部命令：合并 stderr，输出存入 $script:LastOut，退出码存入 $script:LastCode
$script:LastOut = @()
$script:LastCode = 0

function Run([string]$exe, [string[]]$argv, [switch]$AllowFail) {
    $script:LastOut = & $exe @argv 2>&1 | ForEach-Object { "$_" }
    $script:LastCode = $LASTEXITCODE
    if ($script:LastCode -ne 0 -and -not $AllowFail) {
        Write-Host ($script:LastOut -join "`n") -ForegroundColor DarkGray
        Die ("$exe " + ($argv -join " ") + " 失败（退出码 $script:LastCode）")
    }
    return , $script:LastOut
}

# ---------- 1. 目录检查 ----------
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Info "工作目录: $root"

foreach ($p in @("codemagic.yaml", "TrackerSweep.xcodeproj\project.pbxproj",
                 "TrackerSweep\Views.swift", "TrackerSweep\Info.plist")) {
    if (-not (Test-Path $p)) { Die "缺少 $p —— 确认在 tracker-sweep 目录里运行" }
}
Ok "工程文件齐全"

# ---------- 2. git ----------
$gitExe = (Get-Command git -ErrorAction SilentlyContinue)
if (-not $gitExe) { Die "没装 git（https://git-scm.com/download/win）" }
Info "git: $($gitExe.Source)"

# ---------- 3. 本地预检（不花云端额度） ----------
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    Info "本地预检…"
    foreach ($s in @("tools\check_pbxproj.py", "tools\check_sources.py", "tools\check_ci.py")) {
        if (Test-Path $s) {
            $o = Run $py.Source @($s) -AllowFail
            if ($LASTEXITCODE -ne 0) {
                Write-Host ($o -join "`n")
                Die "预检失败: $s"
            }
        }
    }
    Ok "预检通过"
} else {
    Warn "没有 python，跳过预检（建议装一个，能在本地先发现工程问题）"
}

# ---------- 4. init / commit ----------
if (-not (Test-Path ".git")) {
    Run $gitExe.Source @("init") | Out-Null
    Ok "git init"
} else {
    Ok "已有 .git"
}

Run $gitExe.Source @("checkout", "-B", $Branch) -AllowFail | Out-Null
Ok "分支 $Branch"

Run $gitExe.Source @("add", "-A") | Out-Null
$status = Run $gitExe.Source @("status", "--porcelain")
if ($status -and $status.Count -gt 0) {
    $n = ($status | Where-Object { $_.Trim() -ne "" }).Count
    $commitArgs = @("-c", "user.name=tracker-sweep", "-c", "user.email=dev@local",
                    "commit", "-m", $Message)
    $co = Run $gitExe.Source $commitArgs
    Ok "已提交 $n 个变更"
    if ($status -match "\.p12|\.mobileprovision|\.ipa") {
        Warn "注意：这次的变更里似乎包含证书/描述文件/ipa，确认 .gitignore 生效再推"
    }
} else {
    Info "没有需要提交的变更"
}

# ---------- 5. remote ----------
Run $gitExe.Source @("remote", "get-url", "origin") -AllowFail | Out-Null
$hasRemote = ($script:LastCode -eq 0)
$existingUrl = if ($hasRemote -and $script:LastOut.Count -gt 0) {
    ($script:LastOut | Select-Object -First 1).Trim()
} else { "" }

if ($hasRemote -and $existingUrl) {
    if ($existingUrl -ne $Repo) {
        if ($Force) {
            Run $gitExe.Source @("remote", "set-url", "origin", $Repo) | Out-Null
            Ok "remote 已改为 $Repo"
        } else {
            Die "origin 已指向 $existingUrl。要改成 $Repo 请加 -Force"
        }
    } else {
        Ok "remote 已是 $Repo"
    }
} else {
    Run $gitExe.Source @("remote", "add", "origin", $Repo) | Out-Null
    Ok "remote → $Repo"
}

# ---------- 6. push ----------
Info "推送 $Branch …"
Run $gitExe.Source @("push", "-u", "origin", $Branch) -AllowFail | Out-Null
if ($script:LastCode -ne 0) {
    Write-Host ($script:LastOut -join "`n") -ForegroundColor DarkGray
    Die "推送失败。常见原因：① 仓库还不存在 ② 没登录（git config credential.helper manager）③ 远端已有提交，需先 git pull --rebase origin $Branch"
}

Ok "推送成功：$Repo ($Branch)"
Write-Host ""
Write-Host "下一步：" -ForegroundColor Cyan
Write-Host "  1) https://codemagic.io → Sign up with GitHub"
Write-Host "  2) Add application → 选这个仓库 → Project type 选 Other"
Write-Host "  3) Start new build → workflow 选 'iOS unsigned IPA'"
Write-Host "  4) 等 3~5 分钟 → Artifacts 下载 .ipa"
Write-Host "  5) Sideloadly 签名安装（详见 CODEMAGIC.md）"
