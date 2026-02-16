# CustomDRS PowerCLI Module Documentation

## Overview

CustomDRS is a comprehensive PowerCLI module that replicates VMware DRS (Distributed Resource Scheduler) functionality, allowing you to manage VMware vSphere cluster resources programmatically. This module provides full control over load balancing, VM placement, resource management, affinity rules, and power management.

## Features

### Core DRS Features
- ✅ **Load Balancing** - Automatically balance CPU and memory across cluster hosts
- ✅ **Initial VM Placement** - Determine optimal host for new VMs
- ✅ **Affinity/Anti-Affinity Rules** - Keep VMs together or separate
- ✅ **Resource Monitoring** - Track cluster resource usage and balance
- ✅ **Aggressiveness Levels** - Control how aggressively to balance (1-5)
- ✅ **Automated Balancing** - Continuous monitoring and automatic migrations
- ✅ **DPM Support** - Distributed Power Management for energy efficiency
- ✅ **Cluster Health Reporting** - Comprehensive health and balance metrics

### Advanced Features
- Multi-cluster support
- Custom placement logic
- Rule-based migrations
- Performance monitoring and alerting
- Audit trail and reporting
- Integration with existing PowerCLI workflows

## Installation

### Prerequisites
- VMware PowerCLI 12.0 or later
- PowerShell 5.1 or PowerShell 7+
- Access to VMware vCenter Server
- Appropriate permissions in vCenter

### Install PowerCLI (if not already installed)
```powershell
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
```

### Import the CustomDRS Module
```powershell
Import-Module .\CustomDRS.psm1
```

## Quick Start

### 1. Connect to vCenter
```powershell
Connect-VIServer -Server "vcenter.domain.com"
```

### 2. Get Your Cluster
```powershell
$cluster = Get-Cluster -Name "Production-Cluster"
```

### 3. Run Load Balancing
```powershell
# View recommendations only
Invoke-CustomDRSLoadBalance -Cluster $cluster

# Apply recommendations automatically
Invoke-CustomDRSLoadBalance -Cluster $cluster -AutoApply
```

## Function Reference

### Invoke-CustomDRSLoadBalance

Performs load balancing across cluster hosts similar to VMware DRS.

**Syntax:**
```powershell
Invoke-CustomDRSLoadBalance 
    -Cluster <Cluster>
    [-AggressivenessLevel <Int32>]
    [-AutoApply]
    [-AffinityRules <Array>]
```

**Parameters:**
- `Cluster` (Required) - The vCenter cluster to balance
- `AggressivenessLevel` (Optional) - DRS aggressiveness (1-5, default: 3)
  - 1 = Very Conservative (only critical moves)
  - 2 = Conservative
  - 3 = Normal (balanced approach)
  - 4 = Aggressive
  - 5 = Very Aggressive (balance at all costs)
- `AutoApply` (Optional) - Automatically apply migrations
- `AffinityRules` (Optional) - Array of affinity rules to respect

**Examples:**
```powershell
# View recommendations with normal aggressiveness
Invoke-CustomDRSLoadBalance -Cluster $cluster

# Conservative balancing for production
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 1

# Aggressive balancing with auto-apply
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 5 -AutoApply

# Balance with affinity rules
Invoke-CustomDRSLoadBalance -Cluster $cluster -AffinityRules $rules -AutoApply
```

**Output:**
Returns an array of migration recommendations with the following properties:
- VM - VM name
- SourceHost - Current host
- TargetHost - Recommended destination host
- Priority - Migration priority (High/Medium/Low)
- ImprovementScore - Expected improvement value
- ResourceType - Primary constraint (CPU/Memory)

---

### Invoke-CustomDRSVMPlacement

Determines optimal host placement for a VM (initial placement).

**Syntax:**
```powershell
Invoke-CustomDRSVMPlacement 
    -Cluster <Cluster>
    [-VM <VirtualMachine>]
    [-RequiredCpuMhz <Int32>]
    [-RequiredMemoryGB <Int32>]
    [-AffinityRules <Array>]
    [-AutoApply]
```

**Parameters:**
- `Cluster` (Required) - The vCenter cluster for VM placement
- `VM` (Optional) - The VM object to place
- `RequiredCpuMhz` (Optional) - Required CPU in MHz (default: 1000)
- `RequiredMemoryGB` (Optional) - Required memory in GB (default: 2)
- `AffinityRules` (Optional) - Affinity rules to respect
- `AutoApply` (Optional) - Automatically migrate VM to recommended host

**Examples:**
```powershell
# Get placement recommendation for existing VM
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM (Get-VM "WebServer01")

# Place new VM with specific requirements
Invoke-CustomDRSVMPlacement -Cluster $cluster -RequiredCpuMhz 4000 -RequiredMemoryGB 16

# Auto-place VM on best host
$vm = Get-VM "NewServer01"
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm -AutoApply

# Place VM respecting affinity rules
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm -AffinityRules $rules -AutoApply
```

**Output:**
Returns an array of host recommendations sorted by score (best first):
- Host - Host name
- Score - Placement score (lower is better)
- CurrentCpuPercent - Current CPU utilization
- ProjectedCpuPercent - CPU utilization after placement
- CurrentMemPercent - Current memory utilization
- ProjectedMemPercent - Memory utilization after placement

---

### New-CustomDRSAffinityRule

Creates an affinity or anti-affinity rule for DRS operations.

**Syntax:**
```powershell
New-CustomDRSAffinityRule 
    -Name <String>
    -Type <String>
    -VMs <Array>
    [-Enabled <Boolean>]
```

**Parameters:**
- `Name` (Required) - Name of the affinity rule
- `Type` (Required) - Rule type: 'Affinity' or 'AntiAffinity'
- `VMs` (Required) - Array of VM names (minimum 2)
- `Enabled` (Optional) - Whether rule is enabled (default: $true)

**Examples:**
```powershell
# Keep domain controllers on separate hosts
$dcRule = New-CustomDRSAffinityRule `
    -Name "DomainControllers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("DC01", "DC02", "DC03")

# Keep web servers together for performance
$webRule = New-CustomDRSAffinityRule `
    -Name "WebServers-Affinity" `
    -Type Affinity `
    -VMs @("Web01", "Web02", "Web03")

# Database cluster affinity
$dbRule = New-CustomDRSAffinityRule `
    -Name "SQL-Cluster-Affinity" `
    -Type Affinity `
    -VMs @("SQL-Node1", "SQL-Node2", "SQL-Witness")
```

**Usage with Load Balancing:**
```powershell
# Collect rules
$rules = @($dcRule, $webRule, $dbRule)

# Apply during load balancing
Invoke-CustomDRSLoadBalance -Cluster $cluster -AffinityRules $rules -AutoApply
```

---

### Get-CustomDRSRecommendations

Gets current DRS recommendations without applying them.

**Syntax:**
```powershell
Get-CustomDRSRecommendations 
    -Cluster <Cluster>
    [-AggressivenessLevel <Int32>]
    [-AffinityRules <Array>]
```

**Parameters:**
- Same as `Invoke-CustomDRSLoadBalance` but without AutoApply option

**Examples:**
```powershell
# Get recommendations
$recs = Get-CustomDRSRecommendations -Cluster $cluster

# Display in table format
$recs | Format-Table VM, SourceHost, TargetHost, Priority, ImprovementScore

# Export to CSV
$recs | Export-Csv "DRS-Recommendations.csv" -NoTypeInformation

# Filter high-priority only
$recs | Where-Object {$_.Priority -eq "High"}
```

---

### Enable-CustomDRSAutoBalance

Enables continuous automatic load balancing.

**Syntax:**
```powershell
Enable-CustomDRSAutoBalance 
    -Cluster <Cluster>
    [-CheckIntervalMinutes <Int32>]
    [-AggressivenessLevel <Int32>]
    [-AffinityRules <Array>]
```

**Parameters:**
- `Cluster` (Required) - The vCenter cluster to monitor
- `CheckIntervalMinutes` (Optional) - Check interval (default: 5 minutes)
- `AggressivenessLevel` (Optional) - DRS aggressiveness (1-5, default: 3)
- `AffinityRules` (Optional) - Affinity rules to respect

**Examples:**
```powershell
# Enable with default settings (check every 5 minutes)
Enable-CustomDRSAutoBalance -Cluster $cluster

# Check every 15 minutes with conservative balancing
Enable-CustomDRSAutoBalance `
    -Cluster $cluster `
    -CheckIntervalMinutes 15 `
    -AggressivenessLevel 2

# With affinity rules
Enable-CustomDRSAutoBalance `
    -Cluster $cluster `
    -CheckIntervalMinutes 10 `
    -AggressivenessLevel 3 `
    -AffinityRules $rules
```

**Note:** This runs continuously until stopped with Ctrl+C. Consider running as a scheduled task or background job.

---

### Get-CustomDRSClusterHealth

Gets comprehensive cluster health and balance metrics.

**Syntax:**
```powershell
Get-CustomDRSClusterHealth -Cluster <Cluster>
```

**Parameters:**
- `Cluster` (Required) - The vCenter cluster to analyze

**Examples:**
```powershell
# Get health report
Get-CustomDRSClusterHealth -Cluster $cluster

# For multiple clusters
Get-Cluster | ForEach-Object {
    Write-Host "`n=== $($_.Name) ===" -ForegroundColor Cyan
    Get-CustomDRSClusterHealth -Cluster $_
}
```

**Output Includes:**
- Cluster summary (hosts, VMs, total resources)
- Load balance score and rating
- Per-host resource utilization
- Identified issues and warnings
- Balance metrics (CPU/Memory standard deviation)

---

### Invoke-CustomDPM

Implements Distributed Power Management (DPM).

**Syntax:**
```powershell
Invoke-CustomDPM 
    -Cluster <Cluster>
    [-TargetUtilization <Int32>]
    [-MinimumHosts <Int32>]
    [-AutoApply]
```

**Parameters:**
- `Cluster` (Required) - The vCenter cluster to analyze
- `TargetUtilization` (Optional) - Target average utilization % (30-90, default: 70)
- `MinimumHosts` (Optional) - Minimum hosts to keep powered on (default: 2)
- `AutoApply` (Optional) - Automatically apply power recommendations

**Examples:**
```powershell
# Get power management recommendations
Invoke-CustomDPM -Cluster $cluster

# Auto-apply with custom target utilization
Invoke-CustomDPM -Cluster $cluster -TargetUtilization 75 -AutoApply

# Keep at least 3 hosts powered on
Invoke-CustomDPM -Cluster $cluster -MinimumHosts 3
```

**Behavior:**
- Powers OFF hosts when cluster utilization is low and capacity allows
- Powers ON standby hosts when cluster utilization is high
- Respects minimum host requirements
- Evacuates VMs before powering off hosts

---

## Use Cases and Scenarios

### Scenario 1: Daily Load Balancing
Run load balancing every morning at 3 AM:
```powershell
# Create scheduled task script
$cluster = Get-Cluster "Production"
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3 -AutoApply
```

### Scenario 2: Maintenance Mode Preparation
Before putting a host in maintenance mode:
```powershell
$host = Get-VMHost "esxi-01.domain.com"
$vms = Get-VM -Location $host

foreach ($vm in $vms) {
    Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm -AutoApply
}

Set-VMHost -VMHost $host -State Maintenance
```

### Scenario 3: High Availability Setup
Ensure critical VMs are separated:
```powershell
# Create anti-affinity rules for HA pairs
$dbRule = New-CustomDRSAffinityRule `
    -Name "Database-HA-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("DB-Primary", "DB-Secondary")

$webRule = New-CustomDRSAffinityRule `
    -Name "Web-LoadBalancers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("LB01", "LB02")

$rules = @($dbRule, $webRule)
Invoke-CustomDRSLoadBalance -Cluster $cluster -AffinityRules $rules -AutoApply
```

### Scenario 4: Resource-Aware Placement
Place VMs based on workload characteristics:
```powershell
# High-memory VMs get placed on hosts with most memory
$highMemVM = Get-VM "SQL-DataWarehouse"
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $highMemVM -AutoApply

# CPU-intensive VMs
$cpuIntensive = Get-VM "VideoEncoder01"
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $cpuIntensive -AutoApply
```

### Scenario 5: Energy Efficiency (Green IT)
Use DPM during off-hours:
```powershell
# During night hours, consolidate VMs and power off excess hosts
Invoke-CustomDPM -Cluster $cluster -TargetUtilization 75 -MinimumHosts 2 -AutoApply

# During business hours, ensure adequate capacity
Invoke-CustomDPM -Cluster $cluster -TargetUtilization 60 -MinimumHosts 4
```

### Scenario 6: Multi-Cluster Management
Balance multiple clusters:
```powershell
$clusters = Get-Cluster

foreach ($clust in $clusters) {
    Write-Host "Balancing $($clust.Name)"
    
    # Check health first
    Get-CustomDRSClusterHealth -Cluster $clust
    
    # Balance if needed
    $recs = Get-CustomDRSRecommendations -Cluster $clust
    if ($recs.Count -gt 0) {
        Invoke-CustomDRSLoadBalance -Cluster $clust -AutoApply
    }
}
```

## Best Practices

### 1. Aggressiveness Levels
- **Level 1-2**: Use for production clusters where stability is critical
- **Level 3**: Good balance for most environments
- **Level 4-5**: Use for development/test or when major rebalancing is needed

### 2. Affinity Rules
- Use anti-affinity for:
  - HA pairs (primary/secondary)
  - Domain controllers
  - Load balancers
  - Critical infrastructure VMs
  
- Use affinity for:
  - Tightly coupled application tiers
  - VMs with high inter-communication
  - Licensing considerations

### 3. Monitoring
- Run health checks regularly
- Set up alerts for poor balance scores (>25)
- Monitor migration success rates
- Keep audit logs of DRS actions

### 4. Testing
- Test in non-production first
- Start with view-only mode (no -AutoApply)
- Gradually increase aggressiveness
- Monitor impact on VM performance

### 5. Automation
- Schedule regular balancing (daily/weekly)
- Use auto-balance for dynamic environments
- Implement alerting for critical imbalances
- Maintain audit trail

## Troubleshooting

### Issue: No Migrations Recommended
**Cause:** Cluster is already balanced or aggressiveness is too low
**Solution:** 
- Check cluster health: `Get-CustomDRSClusterHealth`
- Increase aggressiveness level
- Verify hosts are powered on and connected

### Issue: Migration Fails
**Cause:** Insufficient resources, locked VMs, or permissions
**Solution:**
- Check destination host has adequate resources
- Verify VM is not locked or in snapshot
- Ensure proper vCenter permissions
- Check for storage constraints

### Issue: Affinity Rule Violations
**Cause:** Insufficient hosts or resources
**Solution:**
- Review affinity rules for conflicts
- Add more hosts to cluster
- Adjust VM resource requirements
- Temporarily disable conflicting rules

### Issue: Poor Balance Score
**Cause:** Workload imbalance or resource constraints
**Solution:**
- Run aggressive load balancing (level 4-5)
- Check for overcommitted resources
- Review VM sizing and resource allocation
- Consider adding cluster capacity

## Performance Considerations

- **Large Clusters**: Balancing may take longer (>50 hosts)
- **Migration Overhead**: Consider vMotion impact on production
- **Frequency**: Don't balance too frequently (every 5-15 minutes minimum)
- **Resource Pools**: Function works at cluster level, not pool level

## Limitations

- Requires VMware PowerCLI and vCenter connectivity
- Does not manage storage DRS (storage balancing)
- Does not handle resource pools directly
- Network considerations not included in scoring
- Does not prevent vMotion storms (rate limit manually)

## Logging and Auditing

### Enable Logging
```powershell
# Start transcript
Start-Transcript -Path "C:\Logs\CustomDRS-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Run operations
Invoke-CustomDRSLoadBalance -Cluster $cluster -AutoApply

# Stop transcript
Stop-Transcript
```

### Create Audit Reports
```powershell
# Generate compliance report
$report = @()
foreach ($clust in Get-Cluster) {
    $metrics = Get-ClusterResourceMetrics -Cluster $clust
    $report += [PSCustomObject]@{
        Cluster = $clust.Name
        Timestamp = Get-Date
        BalanceScore = (Calculate-LoadBalanceScore -Metrics $metrics).Score
        HostCount = $metrics.Count
        VMCount = ($metrics | Measure-Object VMCount -Sum).Sum
    }
}
$report | Export-Csv "DRS-Audit.csv" -NoTypeInformation
```

## Integration with vCenter DRS

CustomDRS can work alongside native vCenter DRS:
- Use CustomDRS for custom logic and automation
- Keep native DRS enabled for other features (HA, admission control)
- Disable native DRS automation if using CustomDRS auto-balance
- CustomDRS respects DRS rules created in vCenter

## Support and Contribution

This module is provided as-is for VMware administrators to manage their clusters.

### Feature Requests
- VM-to-host affinity rules
- Storage DRS integration
- Network-aware placement
- Cost optimization metrics
- Integration with monitoring tools

## Version History

**v1.0** - Initial release
- Core load balancing
- Initial placement
- Affinity rules
- Health monitoring
- DPM support

## License

This module is provided free for use in VMware environments.

## Credits

Developed for VMware vSphere administrators who need programmatic control over DRS operations beyond the native vCenter capabilities.
