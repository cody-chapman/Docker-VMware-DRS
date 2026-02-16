# Install-CustomDRS.ps1
# Installation and setup script for CustomDRS module

<#
.SYNOPSIS
Installs and configures the CustomDRS PowerCLI module

.DESCRIPTION
This script helps you install PowerCLI (if needed), set up the CustomDRS module,
and optionally create scheduled tasks for automated load balancing

.EXAMPLE
.\Install-CustomDRS.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\CustomDRS",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateScheduledTask,
    
    [Parameter(Mandatory=$false)]
    [string]$VCenterServer,
    
    [Parameter(Mandatory=$false)]
    [string]$ClusterName
)

Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║               CustomDRS Installation Script                   ║
║         VMware DRS-Equivalent PowerCLI Module                 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Step 1: Check for PowerShell version
Write-Host "`n[1/6] Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "    PowerShell version: $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor Gray

if ($psVersion.Major -lt 5) {
    Write-Host "    ❌ PowerShell 5.1 or later required" -ForegroundColor Red
    Write-Host "    Please upgrade PowerShell: https://aka.ms/powershell" -ForegroundColor Red
    exit 1
}
Write-Host "    ✓ PowerShell version is compatible" -ForegroundColor Green

# Step 2: Check for PowerCLI
Write-Host "`n[2/6] Checking for VMware PowerCLI..." -ForegroundColor Yellow
$powerCLI = Get-Module -ListAvailable -Name VMware.PowerCLI

if (-not $powerCLI) {
    Write-Host "    VMware PowerCLI not found" -ForegroundColor Yellow
    $install = Read-Host "    Would you like to install PowerCLI now? (Y/N)"
    
    if ($install -eq 'Y' -or $install -eq 'y') {
        Write-Host "    Installing VMware PowerCLI..." -ForegroundColor Yellow
        Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber
        Write-Host "    ✓ PowerCLI installed successfully" -ForegroundColor Green
    }
    else {
        Write-Host "    ❌ PowerCLI is required for CustomDRS" -ForegroundColor Red
        Write-Host "    Install it manually: Install-Module -Name VMware.PowerCLI" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "    ✓ PowerCLI version $($powerCLI.Version) found" -ForegroundColor Green
}

# Step 3: Set PowerCLI configuration
Write-Host "`n[3/6] Configuring PowerCLI settings..." -ForegroundColor Yellow
try {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope User | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope User | Out-Null
    Write-Host "    ✓ PowerCLI configured" -ForegroundColor Green
}
catch {
    Write-Host "    ⚠ Could not configure PowerCLI: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 4: Create module directory
Write-Host "`n[4/6] Installing CustomDRS module..." -ForegroundColor Yellow
Write-Host "    Install path: $InstallPath" -ForegroundColor Gray

if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "    ✓ Module directory created" -ForegroundColor Green
}

# Copy module files
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceModule = Join-Path $scriptPath "CustomDRS.psm1"

if (Test-Path $sourceModule) {
    Copy-Item -Path $sourceModule -Destination $InstallPath -Force
    Write-Host "    ✓ CustomDRS.psm1 copied" -ForegroundColor Green
}
else {
    Write-Host "    ❌ Could not find CustomDRS.psm1" -ForegroundColor Red
    exit 1
}

# Copy documentation if available
$docs = @("README.md", "CustomDRS-Documentation.md", "CustomDRS-Examples.ps1")
foreach ($doc in $docs) {
    $sourcePath = Join-Path $scriptPath $doc
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $InstallPath -Force
        Write-Host "    ✓ $doc copied" -ForegroundColor Green
    }
}

# Step 5: Verify installation
Write-Host "`n[5/6] Verifying installation..." -ForegroundColor Yellow
try {
    Import-Module "$InstallPath\CustomDRS.psm1" -Force
    $functions = Get-Command -Module CustomDRS
    Write-Host "    ✓ Module loaded successfully" -ForegroundColor Green
    Write-Host "    Available functions: $($functions.Count)" -ForegroundColor Gray
}
catch {
    Write-Host "    ❌ Failed to load module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 6: Optional scheduled task setup
if ($CreateScheduledTask) {
    Write-Host "`n[6/6] Creating scheduled task..." -ForegroundColor Yellow
    
    if (-not $VCenterServer) {
        $VCenterServer = Read-Host "    Enter vCenter server address"
    }
    
    if (-not $ClusterName) {
        $ClusterName = Read-Host "    Enter cluster name"
    }
    
    # Save credentials
    $credPath = "$InstallPath\vcenter-creds.xml"
    Write-Host "    Please enter vCenter credentials..." -ForegroundColor Gray
    $credential = Get-Credential -Message "Enter vCenter credentials"
    $credential | Export-Clixml -Path $credPath
    
    # Create scheduled task script
    $taskScript = @"
# Auto-generated CustomDRS scheduled task script
Import-Module "$InstallPath\CustomDRS.psm1"

`$credential = Import-Clixml -Path "$credPath"
Connect-VIServer -Server "$VCenterServer" -Credential `$credential

`$cluster = Get-Cluster -Name "$ClusterName"
Invoke-CustomDRSLoadBalance -Cluster `$cluster -AggressivenessLevel 3 -AutoApply

`$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$logFile = "$InstallPath\CustomDRS-Log.txt"
"`$timestamp - Load balancing completed" | Out-File -FilePath `$logFile -Append

Disconnect-VIServer -Server "$VCenterServer" -Confirm:`$false
"@
    
    $taskScriptPath = "$InstallPath\CustomDRS-ScheduledTask.ps1"
    $taskScript | Out-File -FilePath $taskScriptPath -Encoding UTF8
    
    # Create scheduled task (daily at 3 AM)
    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$taskScriptPath`""
        
        $trigger = New-ScheduledTaskTrigger -Daily -At 3AM
        
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
        
        Register-ScheduledTask -TaskName "CustomDRS-DailyBalance" `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Description "Daily CustomDRS load balancing for $ClusterName" `
            -Force | Out-Null
        
        Write-Host "    ✓ Scheduled task created (runs daily at 3 AM)" -ForegroundColor Green
    }
    catch {
        Write-Host "    ⚠ Could not create scheduled task: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "    You can manually create a scheduled task later" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n[6/6] Skipping scheduled task creation" -ForegroundColor Gray
}

# Summary
Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║              Installation Complete! ✓                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

CustomDRS has been installed to:
  $InstallPath

Getting Started:
  1. Import the module:
     Import-Module CustomDRS

  2. Connect to vCenter:
     Connect-VIServer -Server vcenter.domain.com

  3. Run your first health check:
     Get-CustomDRSClusterHealth -Cluster (Get-Cluster)

  4. View load balancing recommendations:
     Invoke-CustomDRSLoadBalance -Cluster (Get-Cluster)

Documentation:
  • README.md - Quick start guide
  • CustomDRS-Documentation.md - Complete function reference
  • CustomDRS-Examples.ps1 - 16 practical examples

Next Steps:
  • Review the examples in CustomDRS-Examples.ps1
  • Test in a non-production cluster first
  • Set up monitoring and alerting as needed

Questions or Issues?
  • Check the documentation in CustomDRS-Documentation.md
  • Review troubleshooting section in README.md

"@ -ForegroundColor Green

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
