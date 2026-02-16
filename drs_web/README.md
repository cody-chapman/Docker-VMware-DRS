# CustomDRS - VMware DRS Equivalent PowerCLI Module

A comprehensive PowerCLI module that replicates and extends VMware DRS (Distributed Resource Scheduler) functionality, providing full programmatic control over cluster load balancing, VM placement, and resource management.

## 🚀 Quick Start

### Prerequisites
```powershell
# Install VMware PowerCLI
Install-Module -Name VMware.PowerCLI -Scope CurrentUser

# Connect to vCenter
Connect-VIServer -Server "vcenter.domain.com"
```

### Basic Usage
```powershell
# Import the module
Import-Module .\CustomDRS.psm1

# Get your cluster
$cluster = Get-Cluster -Name "Production-Cluster"

# Run load balancing analysis
Invoke-CustomDRSLoadBalance -Cluster $cluster

# Apply recommendations automatically
Invoke-CustomDRSLoadBalance -Cluster $cluster -AutoApply
```

## 📦 What's Included

- **CustomDRS.psm1** - Main PowerShell module with all DRS functions
- **CustomDRS-Examples.ps1** - 16 practical usage examples
- **CustomDRS-Documentation.md** - Complete documentation

## ✨ Key Features

### Core DRS Capabilities
- ✅ **Load Balancing** - Automatically balance CPU and memory across hosts
- ✅ **Initial VM Placement** - Intelligent host selection for new VMs
- ✅ **Affinity/Anti-Affinity Rules** - Control VM placement relationships
- ✅ **Aggressiveness Levels** - Fine-tune balancing behavior (1-5)
- ✅ **Automated Monitoring** - Continuous load balancing
- ✅ **DPM Support** - Distributed Power Management for energy savings
- ✅ **Cluster Health Reports** - Comprehensive resource analytics

### Advanced Features
- Multi-cluster management
- Custom placement algorithms
- Performance monitoring and alerting
- Audit trail and compliance reporting
- Integration with existing workflows
- Scheduled automation support

## 🎯 Main Functions

| Function | Description |
|----------|-------------|
| `Invoke-CustomDRSLoadBalance` | Perform cluster load balancing |
| `Invoke-CustomDRSVMPlacement` | Determine optimal VM placement |
| `New-CustomDRSAffinityRule` | Create affinity/anti-affinity rules |
| `Get-CustomDRSRecommendations` | View recommendations without applying |
| `Enable-CustomDRSAutoBalance` | Enable continuous auto-balancing |
| `Get-CustomDRSClusterHealth` | Get comprehensive health report |
| `Invoke-CustomDPM` | Distributed Power Management |

## 📖 Usage Examples

### Example 1: Load Balancing
```powershell
# View recommendations
$recommendations = Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3

# Apply automatically
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3 -AutoApply
```

### Example 2: VM Placement
```powershell
# Find best host for a VM
$vm = Get-VM "NewServer01"
$placements = Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm

# Auto-place on best host
Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm -AutoApply
```

### Example 3: Affinity Rules
```powershell
# Keep domain controllers separate
$dcRule = New-CustomDRSAffinityRule `
    -Name "DomainControllers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("DC01", "DC02", "DC03")

# Keep web servers together
$webRule = New-CustomDRSAffinityRule `
    -Name "WebServers-Affinity" `
    -Type Affinity `
    -VMs @("Web01", "Web02")

# Apply rules during balancing
$rules = @($dcRule, $webRule)
Invoke-CustomDRSLoadBalance -Cluster $cluster -AffinityRules $rules -AutoApply
```

### Example 4: Continuous Auto-Balancing
```powershell
# Enable auto-balance (runs continuously)
Enable-CustomDRSAutoBalance `
    -Cluster $cluster `
    -CheckIntervalMinutes 10 `
    -AggressivenessLevel 3
```

### Example 5: Cluster Health Monitoring
```powershell
# Get comprehensive health report
Get-CustomDRSClusterHealth -Cluster $cluster
```

### Example 6: Power Management (DPM)
```powershell
# Get power recommendations
Invoke-CustomDPM -Cluster $cluster -TargetUtilization 70 -MinimumHosts 2

# Auto-apply (powers off underutilized hosts)
Invoke-CustomDPM -Cluster $cluster -TargetUtilization 70 -MinimumHosts 2 -AutoApply
```

## 🎚️ Aggressiveness Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| 1 | Very Conservative | Production - only critical moves |
| 2 | Conservative | Stable production environments |
| 3 | Normal | General purpose (default) |
| 4 | Aggressive | Test/dev or major rebalancing |
| 5 | Very Aggressive | Achieve perfect balance |

## 🔄 Common Workflows

### Daily Maintenance
```powershell
# Morning health check and balance
$cluster = Get-Cluster "Production"
Get-CustomDRSClusterHealth -Cluster $cluster
Invoke-CustomDRSLoadBalance -Cluster $cluster -AggressivenessLevel 3 -AutoApply
```

### Pre-Maintenance
```powershell
# Before putting host in maintenance mode
$host = Get-VMHost "esxi-01"
$vms = Get-VM -Location $host
foreach ($vm in $vms) {
    Invoke-CustomDRSVMPlacement -Cluster $cluster -VM $vm -AutoApply
}
```

### Multi-Cluster Management
```powershell
# Balance all clusters
Get-Cluster | ForEach-Object {
    Invoke-CustomDRSLoadBalance -Cluster $_ -AggressivenessLevel 3 -AutoApply
}
```

## 📊 Understanding Load Balance Score

The load balance score represents cluster imbalance:
- **< 5**: Excellent balance ✅
- **5-10**: Good balance ✅
- **10-20**: Fair balance ⚠️
- **> 20**: Poor balance - action recommended ❌

Lower scores are better. Score is calculated from CPU and memory standard deviation across hosts.

## 🔧 Troubleshooting

### No Migrations Recommended
- Cluster is already balanced
- Try increasing aggressiveness level
- Check if all hosts are powered on

### Migration Fails
- Verify sufficient resources on target host
- Check VM is not locked or in snapshot
- Ensure proper vCenter permissions

### High Balance Score
- Run aggressive load balancing (level 4-5)
- Review VM resource allocation
- Consider adding cluster capacity

## 📝 Best Practices

1. **Start Conservative** - Begin with aggressiveness level 1-2
2. **Test First** - Use view-only mode before auto-applying
3. **Monitor Impact** - Watch VM performance during migrations
4. **Schedule Wisely** - Run during low-usage periods
5. **Use Affinity Rules** - Enforce HA and licensing requirements
6. **Regular Health Checks** - Monitor cluster balance weekly
7. **Audit Changes** - Keep logs of all DRS actions

## 🔒 Permissions Required

Your vCenter account needs:
- Read access to clusters and hosts
- VM migration permissions (for AutoApply)
- Power management permissions (for DPM)

## ⚠️ Important Notes

- Does not manage storage DRS (datastore balancing)
- Works at cluster level, not resource pool level
- Cannot prevent vMotion storms - use appropriate intervals
- Network topology not considered in placement scoring
- Large clusters (50+ hosts) may take longer to analyze

## 🆚 Comparison with Native DRS

| Feature | CustomDRS | Native DRS |
|---------|-----------|------------|
| Load Balancing | ✅ | ✅ |
| Initial Placement | ✅ | ✅ |
| Affinity Rules | ✅ | ✅ |
| DPM | ✅ | ✅ |
| Programmable | ✅ | ⚠️ Limited |
| Custom Logic | ✅ | ❌ |
| Multi-Cluster | ✅ | ❌ |
| Cost | Free | Included |
| Support | Community | VMware |

## 📚 Additional Resources

- **CustomDRS-Documentation.md** - Full function reference and detailed guides
- **CustomDRS-Examples.ps1** - 16 real-world usage examples
- VMware PowerCLI Documentation: https://developer.vmware.com/powercli

## 🤝 Use Cases

- **DevOps Automation** - Integrate DRS into CI/CD pipelines
- **Cost Optimization** - Use DPM to reduce power consumption
- **Compliance** - Enforce specific placement policies
- **Multi-Tenant** - Custom placement logic per tenant
- **Disaster Recovery** - Automated rebalancing after failover
- **Capacity Planning** - Analyze "what-if" scenarios

## 💡 Pro Tips

1. **Combine with Native DRS**: Keep native DRS for HA/admission control, use CustomDRS for custom automation
2. **Create Rule Sets**: Build standardized affinity rules for common patterns (DC separation, app tiers, etc.)
3. **Use Scheduled Tasks**: Automate daily balancing via Windows Task Scheduler
4. **Export Metrics**: Track balance scores over time for trend analysis
5. **Test Placement First**: Use `-VM` parameter without `-AutoApply` to preview recommendations

## 🔮 Future Enhancements

Potential additions (not currently implemented):
- VM-to-host affinity rules
- Storage DRS integration
- Network-aware placement
- Machine learning-based predictions
- Integration with monitoring tools (vROps, etc.)

## 📄 License

This module is provided as-is for use in VMware environments. Free to use, modify, and distribute.

## 🙏 Acknowledgments

Created for VMware administrators who need programmatic control over DRS operations beyond native vCenter capabilities.

---

**Questions?** Review the full documentation in `CustomDRS-Documentation.md` or explore the examples in `CustomDRS-Examples.ps1`.

**Ready to get started?** Import the module and run your first health check:
```powershell
Import-Module .\CustomDRS.psm1
Get-CustomDRSClusterHealth -Cluster (Get-Cluster)
```
