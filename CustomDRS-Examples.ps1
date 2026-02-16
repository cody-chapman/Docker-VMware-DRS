# CustomDRS-Examples.ps1
# Example scripts demonstrating how to use the CustomDRS module

<#
.SYNOPSIS
Example scripts for using the CustomDRS PowerCLI module

.DESCRIPTION
This file contains practical examples for using all CustomDRS functions
to manage VMware cluster resources similar to VMware DRS
#>

# ============================================================================
# SETUP - Connect to vCenter
# ============================================================================

# Import the CustomDRS module
Import-Module .\CustomDRS.psm1 -Force

# Connect to vCenter (update with your details)
$vcServer = "vcenter.domain.com"
$credential = Get-Credential
Connect-VIServer -Server $vcServer -Credential $credential

# Get your cluster
$cluster = Get-Cluster -Name "Production-Cluster"

# ============================================================================
# EXAMPLE 1: Basic Load Balancing Analysis
# ============================================================================
Write-Host "`n=== EXAMPLE 1: Basic Load Balancing ===" -ForegroundColor Magenta

# Get recommendations without applying them
$recommendations = Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3

# Review recommendations
$recommendations | Format-Table VM, SourceHost, TargetHost, Priority, ImprovementScore -AutoSize

# ============================================================================
# EXAMPLE 2: Aggressive Load Balancing with Auto-Apply
# ============================================================================
Write-Host "`n=== EXAMPLE 2: Aggressive Load Balancing ===" -ForegroundColor Magenta

# Apply aggressive balancing automatically
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 5 -AutoApply

# ============================================================================
# EXAMPLE 3: Initial VM Placement
# ============================================================================
Write-Host "`n=== EXAMPLE 3: VM Placement ===" -ForegroundColor Magenta

# Get placement recommendation for a new VM
$newVM = Get-VM -Name "NewWebServer01"
$placements = Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $newVM

# Show top 3 recommendations
$placements | Select-Object -First 3 | Format-Table Host, Score, ProjectedCpuPercent, ProjectedMemPercent -AutoSize

# Auto-place VM on best host
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $newVM -AutoApply

# ============================================================================
# EXAMPLE 4: Affinity and Anti-Affinity Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 4: Affinity Rules ===" -ForegroundColor Magenta

# Create anti-affinity rule for domain controllers (should be on different hosts)
$dcRule = New-CustomDRSAffinityRule `
    -Name "DomainControllers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("DC01", "DC02", "DC03")

# Create affinity rule for web tier (should be on same host for performance)
$webRule = New-CustomDRSAffinityRule `
    -Name "WebTier-Affinity" `
    -Type Affinity `
    -VMs @("WebFrontEnd01", "WebFrontEnd02")

# Create affinity rule for database cluster (should be together)
$dbRule = New-CustomDRSAffinityRule `
    -Name "DatabaseCluster-Affinity" `
    -Type Affinity `
    -VMs @("SQL01-Node1", "SQL01-Node2", "SQL01-Witness")

# Collect all rules
$affinityRules = @($dcRule, $webRule, $dbRule)

# Run load balancing respecting affinity rules
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3 -AffinityRules $affinityRules

# ============================================================================
# EXAMPLE 5: VM Placement with Affinity Rules
# ============================================================================
Write-Host "`n=== EXAMPLE 5: VM Placement with Rules ===" -ForegroundColor Magenta

# Place a new domain controller respecting anti-affinity with existing DCs
$newDC = Get-VM -Name "DC04"
Invoke-CustomDRSVMPlacement `
    -Cluster $cluster `
    -VM $newDC `
    -AffinityRules $affinityRules `
    -AutoApply

# ============================================================================
# EXAMPLE 6: Cluster Health Monitoring
# ============================================================================
Write-Host "`n=== EXAMPLE 6: Cluster Health Report ===" -ForegroundColor Magenta

# Get comprehensive cluster health report
Get-CustomDRSClusterHealth -Cluster $cluster

# ============================================================================
# EXAMPLE 7: Just Get Recommendations (No Changes)
# ============================================================================
Write-Host "`n=== EXAMPLE 7: View-Only Recommendations ===" -ForegroundColor Magenta

# Get recommendations without applying
$recs = Get-CustomDRSRecommendations -Cluster $cluster -AggressivenessLevel 3

# Export to CSV for review
$recs | Export-Csv -Path "C:\DRS-Recommendations-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation

# Filter high-priority recommendations only
$highPriority = $recs | Where-Object {$_.Priority -eq "High"}
$highPriority | Format-Table VM, SourceHost, TargetHost, ImprovementScore -AutoSize

# ============================================================================
# EXAMPLE 8: Automated Continuous Balancing
# ============================================================================
Write-Host "`n=== EXAMPLE 8: Continuous Auto-Balance ===" -ForegroundColor Magenta

# Enable continuous automatic balancing (runs until stopped with Ctrl+C)
# Checks every 10 minutes and automatically applies migrations if needed
Enable-CustomDRSAutoBalance `
    -Cluster $cluster `
    -CheckIntervalMinutes 10 `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules

# ============================================================================
# EXAMPLE 9: Conservative Balancing for Production
# ============================================================================
Write-Host "`n=== EXAMPLE 9: Conservative Production Balancing ===" -ForegroundColor Magenta

# Use conservative settings for production cluster
# Only migrates VMs when there's significant imbalance
Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 1 `
    -AffinityRules $affinityRules

# ============================================================================
# EXAMPLE 10: Distributed Power Management (DPM)
# ============================================================================
Write-Host "`n=== EXAMPLE 10: Power Management ===" -ForegroundColor Magenta

# Get power management recommendations
$dpmRec = Invoke-CustomDPM -Cluster $cluster -TargetUtilization 70 -MinimumHosts 2

# Auto-apply power recommendations (power off underutilized hosts)
Invoke-CustomDPM -Cluster $cluster -TargetUtilization 70 -MinimumHosts 2 -AutoApply

# ============================================================================
# EXAMPLE 11: Multi-Cluster Management
# ============================================================================
Write-Host "`n=== EXAMPLE 11: Multi-Cluster Management ===" -ForegroundColor Magenta

# Balance multiple clusters
$clusters = Get-Cluster

foreach ($clust in $clusters) {
    Write-Host "`nProcessing cluster: $($clust.Name)" -ForegroundColor Yellow
    
    # Get health report
    Get-CustomDRSClusterHealth -Cluster $clust
    
    # Get recommendations
    $recs = Get-CustomDRSRecommendations -Cluster $clust -AggressivenessLevel 3
    
    if ($recs -and $recs.Count -gt 0) {
        Write-Host "Found $($recs.Count) recommendations for $($clust.Name)" -ForegroundColor Yellow
    }
}

# ============================================================================
# EXAMPLE 12: Scheduled Load Balancing (Windows Task Scheduler)
# ============================================================================
Write-Host "`n=== EXAMPLE 12: Scheduled Balancing ===" -ForegroundColor Magenta

# This script can be scheduled to run periodically
# Save this as a separate script file and schedule it

$scriptBlock = {
    param($vcServer, $clusterName, $credFile)
    
    # Import module
    Import-Module "C:\Scripts\CustomDRS.psm1"
    
    # Load credentials from file
    $credential = Import-Clixml -Path $credFile
    
    # Connect to vCenter
    Connect-VIServer -Server $vcServer -Credential $credential
    
    # Get cluster
    $cluster = Get-Cluster -Name $clusterName
    
    # Run balancing
    $recs = Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3 -AutoApply
    
    # Log results
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = "C:\Logs\CustomDRS-$(Get-Date -Format 'yyyyMMdd').log"
    
    if ($recs) {
        "$timestamp - Applied $($recs.Count) migrations" | Out-File -FilePath $logFile -Append
    } else {
        "$timestamp - No migrations needed" | Out-File -FilePath $logFile -Append
    }
    
    # Disconnect
    Disconnect-VIServer -Server $vcServer -Confirm:$false
}

# Save credentials once
# $credential = Get-Credential
# $credential | Export-Clixml -Path "C:\Scripts\vcenter-creds.xml"

# Create scheduled task (run as Administrator)
# $trigger = New-ScheduledTaskTrigger -Daily -At 3AM
# $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\CustomDRS-Scheduled.ps1"
# Register-ScheduledTask -TaskName "CustomDRS-DailyBalance" -Trigger $trigger -Action $action -RunLevel Highest

# ============================================================================
# EXAMPLE 13: Maintenance Mode Preparation
# ============================================================================
Write-Host "`n=== EXAMPLE 13: Prepare Host for Maintenance ===" -ForegroundColor Magenta

# Before putting a host in maintenance mode, balance its VMs across other hosts
$hostToMaintain = Get-VMHost -Name "esxi-host-03.domain.com"

# Get VMs on the host
$vmsToEvacuate = Get-VM -Location $hostToMaintain

Write-Host "VMs to evacuate: $($vmsToEvacuate.Count)"

# For each VM, find best placement
foreach ($vm in $vmsToEvacuate) {
    Write-Host "Finding placement for $($vm.Name)..."
    
    Invoke-CustomDRSVMPlacement `
        -Cluster $cluster `
        -VM $vm `
        -AutoApply
    
    Start-Sleep -Seconds 2
}

# Now enter maintenance mode
# Set-VMHost -VMHost $hostToMaintain -State Maintenance

# ============================================================================
# EXAMPLE 14: Performance Monitoring and Alerting
# ============================================================================
Write-Host "`n=== EXAMPLE 14: Performance Monitoring ===" -ForegroundColor Magenta

# Monitor cluster balance and send email alert if poor
$health = Get-CustomDRSClusterHealth -Cluster $cluster

# Calculate balance score
$metrics = Get-ClusterResourceMetrics -Cluster $cluster
$balanceScore = Calculate-LoadBalanceScore -Metrics $metrics

if ($balanceScore.Score -gt 25) {
    # Cluster is poorly balanced - send alert
    $emailParams = @{
        To = "vmware-admins@domain.com"
        From = "drs-monitor@domain.com"
        Subject = "ALERT: Cluster $($cluster.Name) is Poorly Balanced"
        Body = @"
The cluster $($cluster.Name) has a high imbalance score: $([math]::Round($balanceScore.Score, 2))

CPU Standard Deviation: $([math]::Round($balanceScore.CpuStdDev, 2))%
Memory Standard Deviation: $([math]::Round($balanceScore.MemStdDev, 2))%

Recommendation: Run load balancing
Invoke-CustomDRSLoadBalance -Cluster '$($cluster.Name)' -AggressivenessLevel 3 -AutoApply
"@
        SmtpServer = "smtp.domain.com"
    }
    
    # Send-MailMessage @emailParams
}

# ============================================================================
# EXAMPLE 15: Custom Placement Logic for Specific Workloads
# ============================================================================
Write-Host "`n=== EXAMPLE 15: Workload-Specific Placement ===" -ForegroundColor Magenta

# Place high-memory VMs on hosts with most available memory
$highMemVMs = Get-VM -Location $cluster | Where-Object {$_.MemoryGB -gt 32}

foreach ($vm in $highMemVMs) {
    Write-Host "Placing high-memory VM: $($vm.Name) ($($vm.MemoryGB) GB)"
    
    $placements = Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm
    
    # Get host with most available memory
    $bestMemHost = $placements | Sort-Object AvailableMemGB -Descending | Select-Object -First 1
    
    if ($vm.VMHost.Name -ne $bestMemHost.Host) {
        Write-Host "  Recommended: Move to $($bestMemHost.Host)"
        # Move-VM -VM $vm -Destination (Get-VMHost $bestMemHost.Host) -Confirm:$false
    }
}

# ============================================================================
# EXAMPLE 16: Export DRS State for Audit
# ============================================================================
Write-Host "`n=== EXAMPLE 16: Audit and Reporting ===" -ForegroundColor Magenta

# Create comprehensive DRS audit report
$auditReport = @()

foreach ($clust in Get-Cluster) {
    $metrics = Get-ClusterResourceMetrics -Cluster $clust
    $balance = Calculate-LoadBalanceScore -Metrics $metrics
    
    $auditReport += [PSCustomObject]@{
        Cluster = $clust.Name
        Timestamp = Get-Date
        HostCount = $metrics.Count
        TotalVMs = ($metrics | Measure-Object -Property VMCount -Sum).Sum
        BalanceScore = [math]::Round($balance.Score, 2)
        AvgCpuUsage = [math]::Round(($metrics | Measure-Object -Property CpuUsagePercent -Average).Average, 2)
        AvgMemUsage = [math]::Round(($metrics | Measure-Object -Property MemUsagePercent -Average).Average, 2)
        CpuStdDev = [math]::Round($balance.CpuStdDev, 2)
        MemStdDev = [math]::Round($balance.MemStdDev, 2)
    }
}

# Export report
$reportPath = "C:\Reports\DRS-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$auditReport | Export-Csv -Path $reportPath -NoTypeInformation

Write-Host "Audit report saved to: $reportPath" -ForegroundColor Green

# ============================================================================
# CLEANUP
# ============================================================================

# Disconnect from vCenter when done
# Disconnect-VIServer -Server $vcServer -Confirm:$false

Write-Host "`n=== Examples Complete ===" -ForegroundColor Green
