# =========================================================
#  OpenAI 多轮对话客户端  (PowerShell)
#  用法：在 PowerShell 中执行  .\chat-openai.ps1
#  命令：
#     exit / quit         退出
#     /clear              清空对话历史
#     /usage              查看累计 token 用量
#     /model [名称]       查看/切换模型（如 /model gpt-4o）
#     /save [文件名]      把对话保存到文本文件
# =========================================================

# 让终端正确显示中文
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding          = [System.Text.Encoding]::UTF8

# ---------- 配置区 ----------
# 密钥优先级：环境变量 OPENAI_API_KEY > 下面手动填写的值
$script:ApiKey   = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { 'sk-proj-************' }
$script:Model    = 'gpt-6-luna'                # 默认模型
$script:Proxy    = 'http://127.0.0.1:7897'     # 代理地址（留空则不代理）
$script:Endpoint = 'https://api.openai.com/v1/chat/completions'
$script:MaxHistory = 20                        # 最多保留的轮次（条数）
$script:LogDir    = 'logs'                     # 导出文件所在目录
# -----------------------------

# 对话历史 与 token 用量统计
$script:messages       = New-Object System.Collections.ArrayList
$script:PromptTokens   = 0
$script:CompletionTokens = 0
$script:TotalTokens    = 0
$script:TotalTime      = 0.0

# 展示累计用量
function Show-Usage {
    Write-Host ("累计用量  |  输入(prompt): " + $script:PromptTokens + "  |  输出(completion): " +
        $script:CompletionTokens + "  |  合计(total): " + $script:TotalTokens) -ForegroundColor Yellow
    Write-Host ("累计耗时  |  " + $script:TotalTime.ToString('0.00') + " 秒") -ForegroundColor Yellow
}

# 把当前对话保存为文本
function Save-Transcript {
    param([string]$Path)
    if ($script:messages.Count -eq 0) {
        Write-Host "[没有对话内容可保存]" -ForegroundColor Yellow
        return
    }
    if (-not $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $Path  = Join-Path $script:LogDir ("chat-" + $stamp + ".txt")
    }
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $lines = @()
    foreach ($m in $script:messages) {
        $who = if ($m.role -eq 'user') { '你' } else { 'ChatGPT' }
        $lines += ("[" + $who + "] " + $m.content)
    }
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host ("[已保存到 " + $Path + "]" ) -ForegroundColor Green
}

# 发送一条用户消息，返回助手回复
function Send-Chat {
    param([string]$UserText)

    [void]$script:messages.Add(@{ role = 'user'; content = $UserText })

    # 历史过长时，从最早开始截断
    while ($script:messages.Count -gt $script:MaxHistory) {
        [void]$script:messages.RemoveAt(0)
    }

    $payload = @{ model = $script:Model; messages = @($script:messages) } |
        ConvertTo-Json -Depth 12

    $headers = @{ Authorization = "Bearer $($script:ApiKey)" }
    $params  = @{
        Uri         = $script:Endpoint
        Method      = 'Post'
        Headers     = $headers
        ContentType = 'application/json'
        Body        = $payload
    }
    if ($script:Proxy) { $params.Proxy = $script:Proxy }

    # 开始计时
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $resp = Invoke-WebRequest @params
        $obj  = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) |
                ConvertFrom-Json
        $reply = $obj.choices[0].message.content

        # 累加本轮 token 用量（老模型可能不返回 usage，做保护）
        if ($obj.usage) {
            $p = if ($null -ne $obj.usage.prompt_tokens)     { $obj.usage.prompt_tokens }     else { 0 }
            $c = if ($null -ne $obj.usage.completion_tokens) { $obj.usage.completion_tokens } else { 0 }
            $t = if ($null -ne $obj.usage.total_tokens)      { $obj.usage.total_tokens }      else { 0 }
            $script:PromptTokens   += $p
            $script:CompletionTokens += $c
            $script:TotalTokens    += $t
            Write-Host ("  本轮用量: prompt " + $p + " / completion " + $c + " / total " + $t) -ForegroundColor DarkGray
        }

        # 停止计时并显示本轮耗时
        $sw.Stop()
        $elapsed = $sw.Elapsed.TotalSeconds
        $script:TotalTime += $elapsed
        Write-Host ("  本轮耗时: " + $elapsed.ToString('0.00') + " 秒  |  累计耗时: " +
            $script:TotalTime.ToString('0.00') + " 秒") -ForegroundColor DarkGray

        # 记录助手回复，实现多轮记忆
        [void]$script:messages.Add(@{ role = 'assistant'; content = $reply })
        return $reply
    }
    catch {
        Write-Host ("[请求失败] " + $_.Exception.Message) -ForegroundColor Red
        # 移除刚才添加的 user 消息，避免污染历史
        if ($script:messages.Count -gt 0) {
            [void]$script:messages.RemoveAt($script:messages.Count - 1)
        }
        return $null
    }
}

# ---------- 主对话循环 ----------
Write-Host "OpenAI 对话已启动 (模型: $($script:Model))" -ForegroundColor Cyan
Write-Host ("自动追加日志: " + $script:RunLog) -ForegroundColor DarkGray
Write-Host "命令: exit退出 / /clear清空 / /usage用量 / /model切换 / /save保存" -ForegroundColor DarkGray

while ($true) {
    Write-Host "`n你: " -NoNewline -ForegroundColor Green
    $line = Read-Host
    if ($null -eq $line) { break }

    # 命令处理
    if ($line -eq 'exit' -or $line -eq 'quit') { break }
    if ($line -eq '/clear') {
        $script:messages.Clear()
        $script:PromptTokens = 0; $script:CompletionTokens = 0; $script:TotalTokens = 0
        Write-Host "[对话历史与用量统计已清空]" -ForegroundColor Yellow
        continue
    }
    if ($line -eq '/usage') { Show-Usage; continue }
    if ($line -eq '/save')  { Save-Transcript; continue }
    if ($line -like '/save *') {
        Save-Transcript ($line.Substring(6).Trim()); continue
    }
    if ($line -eq '/model') { Write-Host ("当前模型: " + $script:Model) -ForegroundColor Yellow; continue }
    if ($line -like '/model *') {
        $script:Model = $line.Substring(7).Trim()
        Write-Host ("已切换模型: " + $script:Model) -ForegroundColor Yellow
        continue
    }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    # 正常发送
    $reply = Send-Chat $line
    if ($null -ne $reply) {
        Write-Host ("ChatGPT: " + $reply) -ForegroundColor Cyan
    }
}

Write-Host "`n再见！" -ForegroundColor Cyan
