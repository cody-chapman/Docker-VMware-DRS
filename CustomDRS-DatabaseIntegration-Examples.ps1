# CustomDRS-DatabaseIntegration-Examples.ps1
# Examples showing how to use CustomDRS with SQLite database for affinity rules

<#
.SYNOPSIS
Examples demonstrating CustomDRS with SQLite database integration

.DESCRIPTION
Shows how to use the database-backed affinity rule system alongside
the main CustomDRS load balancing functions
#>

# Import both modules
Import-Module .\CustomDRS.psm1 -Force
Import-Module .\CustomDRS-Database.psm1 -Force

# Connect to vCenter
$vcServer = "vcenter.domain.com"
Connect-VIServer -Server $vcServer

$cluster = Get-Cluster -Name "Production-Cluster"

# ============================================================================
# EXAMPLE 1: Initialize Database
# ============================================================================
Write-Host "`n=== EXAMPLE 1: Initialize Database ===" -ForegroundColor Magenta

# Create the database (only needed once)
Initialize-CustomDRSDatabase -DatabasePath "C:\CustomDRS\rules.db"

# ============================================================================
# EXAMPLE 2: Add Rules to Database
# ============================================================================
Write-Host "`n=== EXAMPLE 2: Add Rules to Database ===" -ForegroundColor Magenta

# Add anti-affinity rule for domain controllers
Add-CustomDRSAffinityRuleDB `
    -Name "DomainControllers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("DC01", "DC02", "DC03") `
    -ClusterName "Production" `
    -Description "Keep domain controllers on separate hosts for HA"

# Add affinity rule for database cluster
Add-CustomDRSAffinityRuleDB `
    -Name "SQL-Cluster-Affinity" `
    -Type Affinity `
    -VMs @("SQL-Node1", "SQL-Node2") `
    -ClusterName "Production" `
    -Description "Keep SQL nodes together for low-latency communication"

# Add anti-affinity rule for web load balancers
Add-CustomDRSAffinityRuleDB `
    -Name "LoadBalancers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("LB01", "LB02") `
    -ClusterName "Production" `
    -Description "Separate load balancers for high availability"

# ============================================================================
# EXAMPLE 3: View All Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 3: View All Rules ===" -ForegroundColor Magenta

# Get all rules
$allRules = Get-CustomDRSAffinityRuleDB
$allRules | Format-Table Name, Type, VMCount, Enabled, ClusterName -AutoSize

# Get only anti-affinity rules
$antiAffinityRules = Get-CustomDRSAffinityRuleDB -Type AntiAffinity
Write-Host "`nAnti-Affinity Rules:"
$antiAffinityRules | Format-Table Name, VMs -AutoSize

# Get only enabled rules
$enabledRules = Get-CustomDRSAffinityRuleDB -EnabledOnly
Write-Host "`nEnabled Rules: $($enabledRules.Count)"

# ============================================================================
# EXAMPLE 4: Update Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 4: Update Rules ===" -ForegroundColor Magenta

# Add a new VM to existing rule
Update-CustomDRSAffinityRuleDB `
    -Name "DomainControllers-AntiAffinity" `
    -AddVMs @("DC04")

# Remove a VM from rule
Update-CustomDRSAffinityRuleDB `
    -Name "SQL-Cluster-Affinity" `
    -RemoveVMs @("SQL-Node2")

# Rename a rule
Update-CustomDRSAffinityRuleDB `
    -Name "LoadBalancers-AntiAffinity" `
    -NewName "WebLB-AntiAffinity"

# Disable a rule temporarily
Update-CustomDRSAffinityRuleDB `
    -Name "SQL-Cluster-Affinity" `
    -Enabled $false

# ============================================================================
# EXAMPLE 5: Use Database Rules with Load Balancing
# ============================================================================
Write-Host "`n=== EXAMPLE 5: Load Balancing with Database Rules ===" -ForegroundColor Magenta

# Get rules from database (only enabled rules)
$dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly -ClusterName "Production"

# Convert database rules to format expected by CustomDRS
$affinityRules = $dbRules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.Type
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

# Run load balancing with database rules
Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules

# ============================================================================
# EXAMPLE 6: Auto-Apply Load Balancing with Database Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 6: Auto-Apply with Database Rules ===" -ForegroundColor Magenta

# Get enabled rules from database
$dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly

# Convert to CustomDRS format
$affinityRules = $dbRules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.Type
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

# Apply load balancing automatically
Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules `
    -AutoApply

# ============================================================================
# EXAMPLE 7: VM Placement with Database Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 7: VM Placement with Database Rules ===" -ForegroundColor Magenta

# Get a new VM
$newVM = Get-VM -Name "DC04"

# Get rules from database
$dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly
$affinityRules = $dbRules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.Type
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

# Find best placement
Invoke-CustomDRSVMPlacement `
    -Cluster $cluster `
    -VM $newVM `
    -AffinityRules $affinityRules `
    -AutoApply

# ============================================================================
# EXAMPLE 8: View Rule History
# ============================================================================
Write-Host "`n=== EXAMPLE 8: View Rule History ===" -ForegroundColor Magenta

# Get history for last 7 days
$history = Get-CustomDRSRuleHistory -Days 7
$history | Format-Table RuleName, Action, ActionDate, ActionBy, Details -AutoSize

# Get history for specific rule
$dcHistory = Get-CustomDRSRuleHistory -Name "DomainControllers-AntiAffinity"
$dcHistory | Format-Table Action, ActionDate, Details -AutoSize

# ============================================================================
# EXAMPLE 9: Track Rule Violations
# ============================================================================
Write-Host "`n=== EXAMPLE 9: Track Rule Violations ===" -ForegroundColor Magenta

# After load balancing, you might discover violations
# Add a violation manually (normally done automatically by CustomDRS)
Add-CustomDRSRuleViolation `
    -RuleName "DomainControllers-AntiAffinity" `
    -VMName "DC01" `
    -HostName "esxi-host-01.domain.com" `
    -ViolationType "AntiAffinityViolation"

# View all violations
$violations = Get-CustomDRSRuleViolations
$violations | Format-Table RuleName, VMName, HostName, ViolationType, DetectedDate -AutoSize

# View only unresolved violations
$unresolvedViolations = Get-CustomDRSRuleViolations -UnresolvedOnly
Write-Host "`nUnresolved Violations: $($unresolvedViolations.Count)"

# ============================================================================
# EXAMPLE 10: Export Rules for Backup
# ============================================================================
Write-Host "`n=== EXAMPLE 10: Export Rules ===" -ForegroundColor Magenta

# Export all rules to JSON
Export-CustomDRSRules -Path "C:\Backup\DRS-Rules-$(Get-Date -Format 'yyyyMMdd').json"

# Export only rules for specific cluster
Export-CustomDRSRules `
    -Path "C:\Backup\Production-Rules.json" `
    -ClusterName "Production"

# ============================================================================
# EXAMPLE 11: Import Rules from Backup
# ============================================================================
Write-Host "`n=== EXAMPLE 11: Import Rules ===" -ForegroundColor Magenta

# Import rules (skip if already exist)
Import-CustomDRSRules -Path "C:\Backup\DRS-Rules-20240215.json"

# Import and overwrite existing rules
Import-CustomDRSRules `
    -Path "C:\Backup\Production-Rules.json" `
    -OverwriteExisting

# ============================================================================
# EXAMPLE 12: Complete Workflow - Add Rules and Balance
# ============================================================================
Write-Host "`n=== EXAMPLE 12: Complete Workflow ===" -ForegroundColor Magenta

# Step 1: Add rules to database
Write-Host "Step 1: Adding rules to database..."

Add-CustomDRSAffinityRuleDB `
    -Name "Exchange-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("Exchange01", "Exchange02", "Exchange03") `
    -ClusterName "Production" `
    -Description "Separate Exchange servers for HA"

Add-CustomDRSAffinityRuleDB `
    -Name "AppTier-Affinity" `
    -Type Affinity `
    -VMs @("App01", "App02") `
    -ClusterName "Production" `
    -Description "Keep app servers together"

# Step 2: View current cluster health
Write-Host "`nStep 2: Checking cluster health..."
Get-CustomDRSClusterHealth -Cluster $cluster

# Step 3: Get rules from database
Write-Host "`nStep 3: Loading rules from database..."
$dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly -ClusterName "Production"
$affinityRules = $dbRules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.Type
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

Write-Host "Loaded $($affinityRules.Count) rules"

# Step 4: Run load balancing with rules
Write-Host "`nStep 4: Running load balancing..."
$recommendations = Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules

# Step 5: Review and optionally apply
if ($recommendations) {
    Write-Host "`nFound $($recommendations.Count) recommendations"
    $recommendations | Format-Table VM, SourceHost, TargetHost, Priority, ImprovementScore -AutoSize
    
    # Prompt to apply
    $apply = Read-Host "Apply these recommendations? (Y/N)"
    if ($apply -eq 'Y' -or $apply -eq 'y') {
        Invoke-CustomDRSLoadBalance `
            -Cluster $cluster `
            -AggressivenessLevel 3 `
            -AffinityRules $affinityRules `
            -AutoApply
    }
}

# ============================================================================
# EXAMPLE 13: Scheduled Task with Database Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 13: Scheduled Task Script ===" -ForegroundColor Magenta

# This can be saved as a separate script and scheduled

$scheduledScript = @'
# Scheduled-DRS-Balance.ps1

Import-Module "C:\CustomDRS\CustomDRS.psm1"
Import-Module "C:\CustomDRS\CustomDRS-Database.psm1"

$credential = Import-Clixml -Path "C:\CustomDRS\vcenter-creds.xml"
Connect-VIServer -Server "vcenter.domain.com" -Credential $credential

$cluster = Get-Cluster -Name "Production"

# Load rules from database
$dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly -DatabasePath "C:\CustomDRS\rules.db"
$affinityRules = $dbRules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.Type
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

# Run load balancing
Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules `
    -AutoApply

# Log results
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"$timestamp - Load balancing completed" | Out-File -FilePath "C:\CustomDRS\log.txt" -Append

Disconnect-VIServer -Confirm:$false
'@

Write-Host "`nScheduled script template created"
Write-Host "Save the above script and schedule it with Task Scheduler"

# ============================================================================
# EXAMPLE 14: Migration from vCenter DRS Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 14: Migrate vCenter Rules to Database ===" -ForegroundColor Magenta

# Note: This requires additional vCenter API work to read native DRS rules
# This is a conceptual example

<#
# Get vCenter DRS rules (pseudo-code - actual implementation would use vCenter API)
$vcenterRules = Get-DrsRule -Cluster $cluster

foreach ($rule in $vcenterRules) {
    # Determine type
    $type = if ($rule.Type -eq "VMAffinity") { "Affinity" } else { "AntiAffinity" }
    
    # Add to database
    Add-CustomDRSAffinityRuleDB `
        -Name $rule.Name `
        -Type $type `
        -VMs $rule.VM `
        -ClusterName $cluster.Name `
        -Description "Migrated from vCenter DRS"
}
#>

# ============================================================================
# EXAMPLE 15: Continuous Monitoring with Database Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 15: Continuous Auto-Balance with Database ===" -ForegroundColor Magenta

# Create a wrapper function that loads rules from database
function Enable-CustomDRSAutoBalanceDB {
    param(
        [Parameter(Mandatory=$true)]
        $Cluster,
        [int]$CheckIntervalMinutes = 10,
        [int]$AggressivenessLevel = 3,
        [string]$DatabasePath = "C:\CustomDRS\rules.db"
    )
    
    Write-Host "=== Custom DRS Auto-Balance with Database ===" -ForegroundColor Green
    Write-Host "Cluster: $($Cluster.Name)"
    Write-Host "Check Interval: $CheckIntervalMinutes minutes"
    Write-Host "Database: $DatabasePath"
    Write-Host "`nPress Ctrl+C to stop...`n"
    
    $iteration = 0
    
    while ($true) {
        $iteration++
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        Write-Host "[$timestamp] Check #$iteration" -ForegroundColor Gray
        
        try {
            # Load rules from database
            $dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly -DatabasePath $DatabasePath
            $affinityRules = $dbRules | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Type = $_.Type
                    VMs = $_.VMs
                    Enabled = $_.Enabled
                }
            }
            
            Write-Host "  Loaded $($affinityRules.Count) rules from database" -ForegroundColor Gray
            
            # Run load balancing
            $recommendations = Invoke-CustomDRSLoadBalance `
                -Cluster $Cluster `
                -AggressivenessLevel $AggressivenessLevel `
                -AffinityRules $affinityRules `
                -AutoApply
            
            if ($null -eq $recommendations -or $recommendations.Count -eq 0) {
                Write-Host "  No migrations needed" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "  Next check in $CheckIntervalMinutes minutes...`n" -ForegroundColor Gray
        Start-Sleep -Seconds ($CheckIntervalMinutes * 60)
    }
}

# Example usage (commented out - would run indefinitely)
# Enable-CustomDRSAutoBalanceDB -Cluster $cluster -CheckIntervalMinutes 10

# ============================================================================
# EXAMPLE 16: Rule Management Interface
# ============================================================================
Write-Host "`n=== EXAMPLE 16: Interactive Rule Management ===" -ForegroundColor Magenta

function Show-RuleManagementMenu {
    param([string]$DatabasePath = "C:\CustomDRS\rules.db")
    
    while ($true) {
        Write-Host "`n=== CustomDRS Rule Management ===" -ForegroundColor Cyan
        Write-Host "1. View all rules"
        Write-Host "2. Add new rule"
        Write-Host "3. Update rule"
        Write-Host "4. Delete rule"
        Write-Host "5. View rule history"
        Write-Host "6. Export rules"
        Write-Host "7. Import rules"
        Write-Host "8. Exit"
        
        $choice = Read-Host "`nSelect option"
        
        switch ($choice) {
            "1" {
                $rules = Get-CustomDRSAffinityRuleDB -DatabasePath $DatabasePath
                $rules | Format-Table Name, Type, VMCount, Enabled, ClusterName -AutoSize
            }
            "2" {
                $name = Read-Host "Rule name"
                $type = Read-Host "Type (Affinity/AntiAffinity)"
                $vmsInput = Read-Host "VMs (comma-separated)"
                $vms = $vmsInput -split ',' | ForEach-Object { $_.Trim() }
                $cluster = Read-Host "Cluster name (optional)"
                
                Add-CustomDRSAffinityRuleDB `
                    -Name $name `
                    -Type $type `
                    -VMs $vms `
                    -ClusterName $cluster `
                    -DatabasePath $DatabasePath
            }
            "3" {
                $name = Read-Host "Rule name to update"
                $addVMs = Read-Host "VMs to add (comma-separated, or press Enter to skip)"
                
                if ($addVMs) {
                    $vms = $addVMs -split ',' | ForEach-Object { $_.Trim() }
                    Update-CustomDRSAffinityRuleDB -Name $name -AddVMs $vms -DatabasePath $DatabasePath
                }
            }
            "4" {
                $name = Read-Host "Rule name to delete"
                Remove-CustomDRSAffinityRuleDB -Name $name -DatabasePath $DatabasePath -Confirm:$true
            }
            "5" {
                $history = Get-CustomDRSRuleHistory -Days 30 -DatabasePath $DatabasePath
                $history | Format-Table RuleName, Action, ActionDate, ActionBy -AutoSize
            }
            "6" {
                $path = Read-Host "Export path"
                Export-CustomDRSRules -Path $path -DatabasePath $DatabasePath
            }
            "7" {
                $path = Read-Host "Import path"
                Import-CustomDRSRules -Path $path -DatabasePath $DatabasePath
            }
            "8" {
                return
            }
        }
    }
}

# Example usage (commented out)
# Show-RuleManagementMenu

Write-Host "`n=== Examples Complete ===" -ForegroundColor Green
Write-Host "Database location: C:\CustomDRS\rules.db (or your specified path)"

# Cleanup
# Disconnect-VIServer -Confirm:$false
