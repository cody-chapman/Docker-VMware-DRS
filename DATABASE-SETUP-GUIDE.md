# CustomDRS SQLite Database Setup Guide

## Overview

The CustomDRS Database module provides persistent storage for affinity and anti-affinity rules using SQLite, eliminating the need to rely on vCenter DRS rules. This gives you full programmatic control over your DRS rules with complete audit trails and history.

## Benefits

✅ **Self-Contained** - All rules stored in a single SQLite database file  
✅ **Independent** - No reliance on vCenter DRS configuration  
✅ **Audit Trail** - Complete history of all rule changes  
✅ **Violation Tracking** - Log and monitor rule violations  
✅ **Import/Export** - Easy backup and migration of rules  
✅ **Programmable** - Full API for automation and integration  

## Prerequisites

### System.Data.SQLite Installation

The database module requires System.Data.SQLite. Here are installation options:

### Option 1: Download from Official Site (Recommended)
1. Visit: https://system.data.sqlite.org/downloads/
2. Download the setup bundle for your platform:
   - For .NET Framework: `sqlite-netFx-full-x64-setup-bundle-xxxx.exe`
   - For .NET Core: `sqlite-netFx-core-x64-setup-bundle-xxxx.exe`
3. Run the installer
4. Restart PowerShell

### Option 2: NuGet Package Manager
```powershell
# Install NuGet if not already installed
Install-PackageProvider -Name NuGet -Force

# Install System.Data.SQLite
Install-Package System.Data.SQLite.Core -ProviderName NuGet -Scope CurrentUser
```

### Option 3: Chocolatey (Windows)
```powershell
choco install sqlite
```

### Verify Installation
```powershell
# Check if SQLite is loaded
[System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "System.Data.SQLite" }
```

## Quick Start

### 1. Import Modules
```powershell
Import-Module .\CustomDRS.psm1
Import-Module .\CustomDRS-Database.psm1
```

### 2. Initialize Database
```powershell
# Create database (run once)
Initialize-CustomDRSDatabase -DatabasePath "C:\CustomDRS\rules.db"
```

### 3. Add Your First Rule
```powershell
# Add anti-affinity rule for domain controllers
Add-CustomDRSAffinityRuleDB `
    -Name "DomainControllers-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("DC01", "DC02", "DC03") `
    -ClusterName "Production" `
    -Description "Keep domain controllers on separate hosts"
```

### 4. Use Rules with Load Balancing
```powershell
# Connect to vCenter
Connect-VIServer -Server "vcenter.domain.com"

# Get cluster
$cluster = Get-Cluster "Production"

# Load rules from database
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

# Run load balancing with rules
Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules `
    -AutoApply
```

## Database Schema

The database contains four main tables:

### AffinityRules
Stores rule definitions
- RuleId (Primary Key)
- RuleName (Unique)
- RuleType (Affinity/AntiAffinity)
- Enabled (Boolean)
- ClusterName
- Description
- CreatedDate, ModifiedDate
- CreatedBy, ModifiedBy

### RuleVMs
Stores VM membership (many-to-many)
- RuleVMId (Primary Key)
- RuleId (Foreign Key)
- VMName
- AddedDate

### RuleHistory
Audit trail of all changes
- HistoryId (Primary Key)
- RuleId
- RuleName
- Action (Created/Updated/Deleted)
- ActionDate
- ActionBy
- Details

### RuleViolations
Tracks rule violations
- ViolationId (Primary Key)
- RuleId (Foreign Key)
- VMName
- HostName
- ViolationType
- DetectedDate
- Resolved (Boolean)
- ResolvedDate

## Common Operations

### Add Rules
```powershell
# Anti-affinity (separate VMs)
Add-CustomDRSAffinityRuleDB `
    -Name "HA-Pair-AntiAffinity" `
    -Type AntiAffinity `
    -VMs @("Primary", "Secondary") `
    -ClusterName "Production"

# Affinity (keep VMs together)
Add-CustomDRSAffinityRuleDB `
    -Name "AppTier-Affinity" `
    -Type Affinity `
    -VMs @("Web01", "Web02", "Cache01") `
    -ClusterName "Production"
```

### View Rules
```powershell
# All rules
Get-CustomDRSAffinityRuleDB | Format-Table

# Filter by type
Get-CustomDRSAffinityRuleDB -Type AntiAffinity

# Filter by cluster
Get-CustomDRSAffinityRuleDB -ClusterName "Production"

# Only enabled rules
Get-CustomDRSAffinityRuleDB -EnabledOnly
```

### Update Rules
```powershell
# Add VMs to rule
Update-CustomDRSAffinityRuleDB -Name "HA-Pair" -AddVMs @("Tertiary")

# Remove VMs from rule
Update-CustomDRSAffinityRuleDB -Name "HA-Pair" -RemoveVMs @("Secondary")

# Rename rule
Update-CustomDRSAffinityRuleDB -Name "Old-Name" -NewName "New-Name"

# Disable rule
Update-CustomDRSAffinityRuleDB -Name "Test-Rule" -Enabled $false
```

### Delete Rules
```powershell
# Remove rule (with confirmation)
Remove-CustomDRSAffinityRuleDB -Name "Old-Rule"

# Remove without confirmation
Remove-CustomDRSAffinityRuleDB -Name "Old-Rule" -Confirm:$false
```

### View History
```powershell
# All changes in last 30 days
Get-CustomDRSRuleHistory -Days 30

# History for specific rule
Get-CustomDRSRuleHistory -Name "DomainControllers-AntiAffinity"
```

### Track Violations
```powershell
# View all violations
Get-CustomDRSRuleViolations

# Only unresolved violations
Get-CustomDRSRuleViolations -UnresolvedOnly

# Add violation manually
Add-CustomDRSRuleViolation `
    -RuleName "HA-Pair" `
    -VMName "Primary" `
    -HostName "esxi-01" `
    -ViolationType "AntiAffinityViolation"
```

### Backup and Restore
```powershell
# Export all rules to JSON
Export-CustomDRSRules -Path "C:\Backup\rules.json"

# Export specific cluster
Export-CustomDRSRules -Path "C:\Backup\prod.json" -ClusterName "Production"

# Import rules
Import-CustomDRSRules -Path "C:\Backup\rules.json"

# Import and overwrite existing
Import-CustomDRSRules -Path "C:\Backup\rules.json" -OverwriteExisting
```

## Integration Workflow

### Daily Automated Balancing
```powershell
# scheduled-balance.ps1

Import-Module "C:\CustomDRS\CustomDRS.psm1"
Import-Module "C:\CustomDRS\CustomDRS-Database.psm1"

$cred = Import-Clixml -Path "C:\CustomDRS\creds.xml"
Connect-VIServer -Server "vcenter" -Credential $cred

$cluster = Get-Cluster "Production"

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

# Log
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"$timestamp - Completed" | Out-File "C:\CustomDRS\log.txt" -Append

Disconnect-VIServer -Confirm:$false
```

Schedule with Task Scheduler:
```powershell
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-File C:\CustomDRS\scheduled-balance.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 3AM

Register-ScheduledTask `
    -TaskName "CustomDRS-DailyBalance" `
    -Action $action `
    -Trigger $trigger `
    -RunLevel Highest
```

## Database Location

### Recommended Locations
- **Single User**: `$env:USERPROFILE\Documents\CustomDRS\rules.db`
- **Shared Team**: `C:\CustomDRS\rules.db` (shared folder)
- **Network Share**: `\\fileserver\CustomDRS\rules.db`

### Default Location
If no path is specified, database is created in:
- Module directory: `[module_path]\CustomDRS.db`

### Specify Custom Location
```powershell
# All functions accept -DatabasePath parameter
Initialize-CustomDRSDatabase -DatabasePath "D:\Data\CustomDRS\rules.db"
Add-CustomDRSAffinityRuleDB -Name "Rule" -Type Affinity -VMs @("VM1") -DatabasePath "D:\Data\CustomDRS\rules.db"
Get-CustomDRSAffinityRuleDB -DatabasePath "D:\Data\CustomDRS\rules.db"
```

## Best Practices

### 1. Regular Backups
```powershell
# Daily export
$date = Get-Date -Format "yyyyMMdd"
Export-CustomDRSRules -Path "C:\Backup\rules-$date.json"
```

### 2. Use Descriptive Names
```powershell
# Good
Add-CustomDRSAffinityRuleDB -Name "Exchange-HA-AntiAffinity" ...

# Bad
Add-CustomDRSAffinityRuleDB -Name "Rule1" ...
```

### 3. Add Descriptions
```powershell
Add-CustomDRSAffinityRuleDB `
    -Name "SQL-Cluster" `
    -Type Affinity `
    -VMs @("SQL01", "SQL02") `
    -Description "SQL Always-On nodes must be co-located for low-latency synchronous replication"
```

### 4. Use ClusterName for Multi-Cluster
```powershell
# Tag rules by cluster
Add-CustomDRSAffinityRuleDB ... -ClusterName "Production"
Add-CustomDRSAffinityRuleDB ... -ClusterName "Development"

# Filter by cluster
$prodRules = Get-CustomDRSAffinityRuleDB -ClusterName "Production"
```

### 5. Review History Regularly
```powershell
# Weekly review
Get-CustomDRSRuleHistory -Days 7 | Out-GridView
```

### 6. Monitor Violations
```powershell
# Check for unresolved violations
$violations = Get-CustomDRSRuleViolations -UnresolvedOnly
if ($violations) {
    Send-MailMessage -To "admin@company.com" -Subject "DRS Rule Violations" ...
}
```

## Troubleshooting

### Issue: "System.Data.SQLite not found"
**Solution**: Install System.Data.SQLite (see Prerequisites section)

### Issue: "Database not found"
**Solution**: Run `Initialize-CustomDRSDatabase` first

### Issue: "Database is locked"
**Solution**: Close any open connections or other processes using the database

### Issue: Rules not being applied
**Check**:
1. Rules are enabled: `Get-CustomDRSAffinityRuleDB -EnabledOnly`
2. VM names match exactly (case-sensitive)
3. Rules are being loaded and converted properly

### Issue: Poor performance with large database
**Solution**: 
- Database is optimized with indexes
- For 1000+ rules, consider filtering by cluster
- Regular maintenance: Export, delete old history, re-import

## Migration from vCenter DRS

To migrate existing vCenter DRS rules to the database:

1. **Document existing rules** in vCenter
2. **Create equivalent rules** in database:
```powershell
# For each vCenter DRS rule, create database entry
Add-CustomDRSAffinityRuleDB `
    -Name "MigratedRule" `
    -Type AntiAffinity `
    -VMs @("VM1", "VM2") `
    -Description "Migrated from vCenter DRS"
```

3. **Test** with view-only mode first
4. **Disable vCenter DRS automation** (keep DRS enabled for HA)
5. **Enable CustomDRS automation**

## Security Considerations

### Database Access
- SQLite file permissions determine access
- For shared database, use NTFS permissions
- Consider encryption for sensitive environments

### Credentials
- Never store credentials in scripts
- Use encrypted credential files:
```powershell
$cred = Get-Credential
$cred | Export-Clixml -Path "C:\CustomDRS\creds.xml"
```

### Audit Trail
- All changes are logged with username and timestamp
- Review history regularly for unauthorized changes

## Performance Notes

- **Database size**: Minimal (< 1MB for hundreds of rules)
- **Query performance**: Sub-millisecond for typical operations
- **Concurrent access**: SQLite supports multiple readers, single writer
- **Backup size**: JSON exports are typically < 100KB

## Support and Troubleshooting

### Enable Verbose Logging
```powershell
$VerbosePreference = "Continue"
Initialize-CustomDRSDatabase -Verbose
```

### Check Database Integrity
```powershell
# Connect to database
Add-Type -Path "path\to\System.Data.SQLite.dll"
$conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=rules.db")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "PRAGMA integrity_check;"
$result = $cmd.ExecuteScalar()
$conn.Close()

Write-Host "Integrity check: $result"
```

### Database Statistics
```powershell
$rules = Get-CustomDRSAffinityRuleDB
$history = Get-CustomDRSRuleHistory -Days 365
$violations = Get-CustomDRSRuleViolations

Write-Host "Rules: $($rules.Count)"
Write-Host "History entries: $($history.Count)"
Write-Host "Violations: $($violations.Count)"
```

## Next Steps

1. **Initialize** your database
2. **Add rules** for your critical VMs
3. **Test** with view-only mode
4. **Enable automation** with AutoApply
5. **Schedule** regular balancing
6. **Monitor** violations and history

For complete examples, see `CustomDRS-DatabaseIntegration-Examples.ps1`
