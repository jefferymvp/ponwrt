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
    if ($LASTEXITCODE -ne 0) {
        $mergeStatus = 1
    }
}

# 5. 冲突检测与用户确认合并
$unmergedFiles = git diff --name-only --diff-filter=U
if ($unmergedFiles) {
    Write-Host "`n[检测] 发现文件冲突！" -ForegroundColor Yellow

    # 筛选属于配置清单类的非互斥文件与其它文件
    $configFiles = @($unmergedFiles | Where-Object { $_ -match '\.(config|conf)$' -or $_ -match '^configs/' -or $_ -match 'feeds\.conf' })
    $otherFiles = @($unmergedFiles | Where-Object { $configFiles -notcontains $_ })

    if ($configFiles.Count -gt 0) {
        Write-Host "`n检测到以下配置文件存在冲突（双方新增内容通常可同时保留）：" -ForegroundColor Cyan
        $configFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }

        $confirm = Read-Host "`n是否尝试自动保留双方配置并合并? (Y/N) [默认 Y]"
        if ([string]::IsNullOrWhiteSpace($confirm)) { $confirm = "Y" }

        if ($confirm -match "^[Yy]") {
            foreach ($file in $configFiles) {
                if (Test-Path $file) {
                    $content = Get-Content -Path $file -Raw -Encoding UTF8
                    if ($content -match '<<<<<<<') {
                        $resolved = [regex]::Replace($content, '(?s)<<<<<<<[^\r\n]*\r?\n(.*?)\r?\n=======\r?\n(.*?)\r?\n>>>>>>>[^\r\n]*', {
                            param($match)
                            $sideUpstream = $match.Groups[1].Value.Trim()
                            $sideLocal = $match.Groups[2].Value.Trim()
                            return "$sideUpstream`r`n`r`n$sideLocal"
                        })
                        Set-Content -Path $file -Value $resolved -Encoding UTF8
                        git add $file
                        Write-Host "  [√] 已自动合并并保留双方配置: $file" -ForegroundColor Green
                    }
                }
            }
        } else {
            Write-Host "已跳过自动合并，冲突标记已保留，请手动检查解决。" -ForegroundColor Yellow
        }
    }

    if ($otherFiles.Count -gt 0) {
        Write-Host "`n[提示] 以下非配置文件（如代码/补丁/脚本）存在逻辑冲突，需手动检查解决:" -ForegroundColor Magenta
        $otherFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }

    # 检查最终是否仍有未解决的冲突
    $remainingConflicts = git diff --name-only --diff-filter=U
    if ($remainingConflicts) {
        $mergeStatus = 1
    } else {
        $mergeStatus = 0
        Write-Host "`n[成功] 冲突已全部解决！" -ForegroundColor Green
        if ($hasChanges) {
            # 解决完毕后清理本次 stash 缓存
            git stash drop >$null 2>&1
        }
    }
}

if ($mergeStatus -ne 0) {
    Write-Host "`n[警告] 本次同步存在未解决的冲突，请处理后提交。" -ForegroundColor Magenta
} else {
    Write-Host "`n[成功] 源码主干与上游同步完成！" -ForegroundColor Green
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "全部流程执行完毕。" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
pause
