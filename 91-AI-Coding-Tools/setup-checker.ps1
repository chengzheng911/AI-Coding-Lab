
# AI Coding Setup Checker
# Version: 1.0
# Purpose: Check local AI coding development prerequisites on Windows.

$ErrorActionPreference = "Continue"

$ReportPath = Join-Path $PSScriptRoot "setup-report.txt"
$Results = [System.Collections.Generic.List[object]]::new()

function Add-CheckResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Details,
        [string]$Suggestion = ""
    )

    $Results.Add([PSCustomObject]@{
        Name       = $Name
        Status     = $Status
        Details    = $Details
        Suggestion = $Suggestion
    })
}

function Test-CommandTool {
    param(
        [string]$Name,
        [string]$Command,
        [string]$VersionArgument = "--version",
        [string]$InstallHint = ""
    )

    $Tool = Get-Command $Command -ErrorAction SilentlyContinue

    if (-not $Tool) {
        Add-CheckResult $Name "MISSING" `
            "Command not found: $Command" $InstallHint
        return
    }

    try {
        $Output = @(& $Command $VersionArgument 2>&1)
        $ExitCode = $LASTEXITCODE

        $Version = ($Output | ForEach-Object {
            "$_"
        } | Select-Object -First 1)

        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Version = "Installed; version output unavailable"
        }

        if ($null -ne $ExitCode -and $ExitCode -ne 0) {
            Add-CheckResult $Name "WARNING" `
                "Command exists but version check returned exit code $ExitCode. $Version" `
                "Check whether the tool is correctly installed."
        }
        else {
            Add-CheckResult $Name "PASS" $Version
        }
    }
    catch {
        Add-CheckResult $Name "WARNING" `
            "Found command, but version check failed." `
            "Verify the installation and PATH configuration."
    }
}

Write-Host ""
Write-Host "======================================"
Write-Host "      AI Coding Setup Checker"
Write-Host "======================================"
Write-Host ""

# 1. Operating system
Add-CheckResult "Operating System" "INFO" `
    "$([System.Environment]::OSVersion.VersionString)"

# 2. Basic development tools
Test-CommandTool "Git" "git" "--version" `
    "Install Git for Windows from https://git-scm.com/download/win"

Test-CommandTool "Python" "python" "--version" `
    "Install Python from https://www.python.org/downloads/"

# Some Windows installations use the py launcher.
Test-CommandTool "Python Launcher" "py" "--version" `
    "Install Python and enable the Python launcher."

Test-CommandTool "Node.js" "node" "--version" `
    "Install Node.js LTS from https://nodejs.org/"

Test-CommandTool "npm" "npm" "--version" `
    "Install Node.js LTS, which includes npm."

# 3. Optional development environments
Test-CommandTool "Flutter" "flutter" "--version" `
    "Install Flutter if your project requires Flutter."

Test-CommandTool "VS Code CLI" "code" "--version" `
    "Install VS Code and enable its command-line PATH option."

# 4. Common AI coding command-line tools
Test-CommandTool "Codex CLI" "codex" "--version" `
    "Install Codex CLI only if required by your service."

Test-CommandTool "Claude Code" "claude" "--version" `
    "Install Claude Code only if required by your service."

# 5. API key presence only.
# Never print, export, or save the key value to the report.
$KeyNames = @("OPENAI_API_KEY", "ANTHROPIC_API_KEY")

foreach ($KeyName in $KeyNames) {
    $KeyValue = [Environment]::GetEnvironmentVariable(
        $KeyName, "Process"
    )

    if ([string]::IsNullOrWhiteSpace($KeyValue)) {
        Add-CheckResult "$KeyName configured" "INFO" `
            "Not found in this PowerShell process." `
            "Configure it only if your workflow requires this API."
    }
    else {
        Add-CheckResult "$KeyName configured" "PASS" `
            "Environment variable exists; value intentionally hidden."
    }
}

# 6. Display results
Write-Host "CHECK RESULTS"
Write-Host "--------------------------------------"

foreach ($Item in $Results) {
    $Line = "[$($Item.Status)] $($Item.Name): $($Item.Details)"
    Write-Host $Line

    if ($Item.Suggestion) {
        Write-Host "         Next step: $($Item.Suggestion)"
    }
}

# 7. Save a text report, excluding secret values.
$Report = @(
    "AI Coding Setup Checker Report"
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Machine: $env:COMPUTERNAME"
    ""
)

foreach ($Item in $Results) {
    $Report += "[$($Item.Status)] $($Item.Name)"
    $Report += "Details: $($Item.Details)"

    if ($Item.Suggestion) {
        $Report += "Next step: $($Item.Suggestion)"
    }

    $Report += ""
}

$Report | Set-Content -Path $ReportPath -Encoding UTF8

$Passed = @($Results | Where-Object {
    $_.Status -eq "PASS"
}).Count

$Missing = @($Results | Where-Object {
    $_.Status -eq "MISSING"
}).Count

$Warnings = @($Results | Where-Object {
    $_.Status -eq "WARNING"
}).Count

Write-Host "--------------------------------------"
Write-Host "PASS: $Passed | MISSING: $Missing | WARNING: $Warnings"
Write-Host "Report saved to: $ReportPath"
Write-Host ""
Write-Host "Note: This is a local environment check."
Write-Host "It does not verify API credentials or billing."