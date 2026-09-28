[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "             PonWrt 上游源码与 Feeds 同步工具          " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. 检查 Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[错误] 未检测到 Git，请确保已安装 Git 并添加到环境变量。" -ForegroundColor Red
    pause
    exit 1
}

# 2. 检查并添加 upstream
$upstreamUrl = "https://github.com/pbs05/ponwrt.git"
$upstreamBranch = "master"

$remotes = git remote
if ($remotes -notcontains "upstream") {
    Write-Host "[提示] 正在添加上游仓库: $upstreamUrl" -ForegroundColor Yellow
    git remote add upstream $upstreamUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 添加 upstream 失败。" -ForegroundColor Red
        pause
        exit 1
    }
} else {
    Write-Host "[信息] 当前已配置 upstream: $upstreamUrl" -ForegroundColor Gray
}

# 3. 拉取上游最新分支
Write-Host "`n[1/2] 正在从 upstream 获取最新提交..." -ForegroundColor Green
git fetch upstream
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 从上游拉取失败，请检查网络连接。" -ForegroundColor Red
    pause
    exit 1
}

# 4. 检查工作区暂存并合并
Write-Host "`n[2/2] 正在检查本地修改并合并上游代码..." -ForegroundColor Green
$hasChanges = $false
git diff --quiet
if ($LASTEXITCODE -ne 0) { $hasChanges = $true }
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { $hasChanges = $true }

if ($hasChanges) {
    Write-Host "[提示] 检测到本地有未提交的改动，正在自动 stash 暂存保护..." -ForegroundColor Yellow
    git stash push -m "auto-stash before upstream sync"
}

Write-Host "正在合并 upstream/$upstreamBranch 到当前分支..." -ForegroundColor Gray
git merge "upstream/$upstreamBranch" --no-edit
$mergeStatus = $LASTEXITCODE

if ($hasChanges) {
    Write-Host "正在恢复本地改动 (git stash pop)..." -ForegroundColor Yellow
    git stash pop
}

if ($mergeStatus -ne 0) {
    Write-Host "`n[警告] 合并时存在冲突，请手动检查解决冲突文件。" -ForegroundColor Magenta
} else {
    Write-Host "`n[成功] 源码主干与上游同步完成！" -ForegroundColor Green
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "全部流程执行完毕。" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
pause
