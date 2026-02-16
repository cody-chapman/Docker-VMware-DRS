# CustomDRS-Database.psm1
# SQLite database module for CustomDRS affinity rules management

<#
.SYNOPSIS
SQLite database functions for CustomDRS affinity rule persistence

.DESCRIPTION
This module provides SQLite database operations for storing and retrieving
affinity and anti-affinity rules, allowing CustomDRS to maintain its own
rule database independent of vCenter DRS rules.
#>

#region Database Setup

function Initialize-CustomDRSDatabase {
    <#
    .SYNOPSIS
    Initializes the CustomDRS SQLite database
    
    .DESCRIPTION
    Creates the SQLite database file and necessary tables for storing
    affinity rules, rule history, and audit logs
    
    .PARAMETER DatabasePath
    Path to the SQLite database file (default: CustomDRS.db in module directory)
    
    .EXAMPLE
    Initialize-CustomDRSDatabase -DatabasePath "C:\CustomDRS\rules.db"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    Write-Verbose "Initializing CustomDRS database at: $DatabasePath"
    
    # Check if System.Data.SQLite is available
    $sqliteAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | 
        Where-Object { $_.GetName().Name -eq "System.Data.SQLite" }
    
    if (-not $sqliteAssembly) {
        Write-Host "System.Data.SQLite not found. Attempting to load..." -ForegroundColor Yellow
        
        # Try to load from common paths
        $possiblePaths = @(
            "C:\Program Files\System.Data.SQLite\*\System.Data.SQLite.dll",
            "$env:ProgramFiles\System.Data.SQLite\*\System.Data.SQLite.dll",
            "${env:ProgramFiles(x86)}\System.Data.SQLite\*\System.Data.SQLite.dll",
            "$PSScriptRoot\System.Data.SQLite.dll"
        )
        
        $foundPath = $null
        foreach ($path in $possiblePaths) {
            $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
            if ($resolved) {
                $foundPath = $resolved | Select-Object -First 1 -ExpandProperty Path
                break
            }
        }
        
        if ($foundPath) {
            try {
                Add-Type -Path $foundPath
                Write-Host "Successfully loaded System.Data.SQLite" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to load System.Data.SQLite: $($_.Exception.Message)"
                Write-Host "`nTo install System.Data.SQLite:" -ForegroundColor Yellow
                Write-Host "1. Download from: https://system.data.sqlite.org/downloads/" -ForegroundColor Yellow
                Write-Host "2. Or install via NuGet: Install-Package System.Data.SQLite.Core" -ForegroundColor Yellow
                return $false
            }
        }
        else {
            Write-Error "System.Data.SQLite not found. Please install it first."
            Write-Host "`nTo install System.Data.SQLite:" -ForegroundColor Yellow
            Write-Host "1. Download from: https://system.data.sqlite.org/downloads/" -ForegroundColor Yellow
            Write-Host "2. Or use the included helper: Install-SQLiteDependency" -ForegroundColor Yellow
            return $false
        }
    }
    
    # Create database connection string
    $connectionString = "Data Source=$DatabasePath;Version=3;"
    
    # Create database file if it doesn't exist
    if (-not (Test-Path $DatabasePath)) {
        Write-Verbose "Creating new database file"
        [void][System.Data.SQLite.SQLiteConnection]::CreateFile($DatabasePath)
    }
    
    try {
        $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
        $connection.Open()
        
        # Create AffinityRules table
        $createRulesTable = @"
CREATE TABLE IF NOT EXISTS AffinityRules (
    RuleId INTEGER PRIMARY KEY AUTOINCREMENT,
    RuleName TEXT NOT NULL UNIQUE,
    RuleType TEXT NOT NULL CHECK(RuleType IN ('Affinity', 'AntiAffinity')),
    Enabled INTEGER NOT NULL DEFAULT 1,
    ClusterName TEXT,
    Description TEXT,
    CreatedDate TEXT NOT NULL,
    ModifiedDate TEXT NOT NULL,
    CreatedBy TEXT,
    ModifiedBy TEXT
);
"@
        
        # Create RuleVMs table (many-to-many relationship)
        $createRuleVMsTable = @"
CREATE TABLE IF NOT EXISTS RuleVMs (
    RuleVMId INTEGER PRIMARY KEY AUTOINCREMENT,
    RuleId INTEGER NOT NULL,
    VMName TEXT NOT NULL,
    AddedDate TEXT NOT NULL,
    FOREIGN KEY (RuleId) REFERENCES AffinityRules(RuleId) ON DELETE CASCADE,
    UNIQUE(RuleId, VMName)
);
"@
        
        # Create RuleHistory table for audit trail
        $createHistoryTable = @"
CREATE TABLE IF NOT EXISTS RuleHistory (
    HistoryId INTEGER PRIMARY KEY AUTOINCREMENT,
    RuleId INTEGER,
    RuleName TEXT NOT NULL,
    Action TEXT NOT NULL,
    ActionDate TEXT NOT NULL,
    ActionBy TEXT,
    Details TEXT
);
"@
        
        # Create RuleViolations table for tracking violations
        $createViolationsTable = @"
CREATE TABLE IF NOT EXISTS RuleViolations (
    ViolationId INTEGER PRIMARY KEY AUTOINCREMENT,
    RuleId INTEGER NOT NULL,
    RuleName TEXT NOT NULL,
    VMName TEXT NOT NULL,
    HostName TEXT NOT NULL,
    ViolationType TEXT NOT NULL,
    DetectedDate TEXT NOT NULL,
    Resolved INTEGER DEFAULT 0,
    ResolvedDate TEXT,
    FOREIGN KEY (RuleId) REFERENCES AffinityRules(RuleId) ON DELETE CASCADE
);
"@
        
        # Create indexes
        $createIndexes = @"
CREATE INDEX IF NOT EXISTS idx_rulevms_ruleid ON RuleVMs(RuleId);
CREATE INDEX IF NOT EXISTS idx_rulevms_vmname ON RuleVMs(VMName);
CREATE INDEX IF NOT EXISTS idx_history_ruleid ON RuleHistory(RuleId);
CREATE INDEX IF NOT EXISTS idx_violations_ruleid ON RuleViolations(RuleId);
CREATE INDEX IF NOT EXISTS idx_violations_resolved ON RuleViolations(Resolved);
"@
        
        # Execute table creation
        $command = $connection.CreateCommand()
        
        $command.CommandText = $createRulesTable
        [void]$command.ExecuteNonQuery()
        
        $command.CommandText = $createRuleVMsTable
        [void]$command.ExecuteNonQuery()
        
        $command.CommandText = $createHistoryTable
        [void]$command.ExecuteNonQuery()
        
        $command.CommandText = $createViolationsTable
        [void]$command.ExecuteNonQuery()
        
        $command.CommandText = $createIndexes
        [void]$command.ExecuteNonQuery()
        
        $connection.Close()
        
        Write-Host "✓ CustomDRS database initialized successfully" -ForegroundColor Green
        Write-Host "  Database location: $DatabasePath" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Error "Failed to initialize database: $($_.Exception.Message)"
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        return $false
    }
}

function Get-DatabaseConnection {
    <#
    .SYNOPSIS
    Gets a SQLite database connection
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    if (-not (Test-Path $DatabasePath)) {
        throw "Database not found at $DatabasePath. Run Initialize-CustomDRSDatabase first."
    }
    
    $connectionString = "Data Source=$DatabasePath;Version=3;"
    $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    $connection.Open()
    
    return $connection
}

#endregion

#region Rule Management

function Add-CustomDRSAffinityRuleDB {
    <#
    .SYNOPSIS
    Adds an affinity or anti-affinity rule to the database
    
    .DESCRIPTION
    Stores a new affinity rule in the SQLite database for persistent storage
    
    .PARAMETER Name
    Name of the affinity rule (must be unique)
    
    .PARAMETER Type
    Type of rule: 'Affinity' or 'AntiAffinity'
    
    .PARAMETER VMs
    Array of VM names that are part of this rule
    
    .PARAMETER ClusterName
    Optional cluster name to associate with the rule
    
    .PARAMETER Description
    Optional description of the rule
    
    .PARAMETER Enabled
    Whether the rule is enabled (default: $true)
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Add-CustomDRSAffinityRuleDB -Name "DC-AntiAffinity" -Type AntiAffinity -VMs @("DC01", "DC02", "DC03") -ClusterName "Production"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Affinity','AntiAffinity')]
        [string]$Type,
        
        [Parameter(Mandatory=$true)]
        [array]$VMs,
        
        [Parameter(Mandatory=$false)]
        [string]$ClusterName,
        
        [Parameter(Mandatory=$false)]
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled = $true,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    if ($VMs.Count -lt 2) {
        Write-Error "Affinity rules require at least 2 VMs"
        return $false
    }
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        $transaction = $connection.BeginTransaction()
        
        try {
            # Insert rule
            $insertRule = @"
INSERT INTO AffinityRules (RuleName, RuleType, Enabled, ClusterName, Description, CreatedDate, ModifiedDate, CreatedBy, ModifiedBy)
VALUES (@Name, @Type, @Enabled, @ClusterName, @Description, @CreatedDate, @ModifiedDate, @CreatedBy, @ModifiedBy);
SELECT last_insert_rowid();
"@
            
            $command = $connection.CreateCommand()
            $command.CommandText = $insertRule
            $command.Transaction = $transaction
            
            [void]$command.Parameters.AddWithValue("@Name", $Name)
            [void]$command.Parameters.AddWithValue("@Type", $Type)
            [void]$command.Parameters.AddWithValue("@Enabled", [int]$Enabled)
            [void]$command.Parameters.AddWithValue("@ClusterName", [string]$ClusterName)
            [void]$command.Parameters.AddWithValue("@Description", [string]$Description)
            [void]$command.Parameters.AddWithValue("@CreatedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
            [void]$command.Parameters.AddWithValue("@ModifiedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
            [void]$command.Parameters.AddWithValue("@CreatedBy", $env:USERNAME)
            [void]$command.Parameters.AddWithValue("@ModifiedBy", $env:USERNAME)
            
            $ruleId = [int]$command.ExecuteScalar()
            
            # Insert VMs
            $insertVM = "INSERT INTO RuleVMs (RuleId, VMName, AddedDate) VALUES (@RuleId, @VMName, @AddedDate);"
            
            foreach ($vm in $VMs) {
                $vmCommand = $connection.CreateCommand()
                $vmCommand.CommandText = $insertVM
                $vmCommand.Transaction = $transaction
                
                [void]$vmCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                [void]$vmCommand.Parameters.AddWithValue("@VMName", $vm)
                [void]$vmCommand.Parameters.AddWithValue("@AddedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                
                [void]$vmCommand.ExecuteNonQuery()
            }
            
            # Add to history
            $insertHistory = @"
INSERT INTO RuleHistory (RuleId, RuleName, Action, ActionDate, ActionBy, Details)
VALUES (@RuleId, @RuleName, 'Created', @ActionDate, @ActionBy, @Details);
"@
            
            $histCommand = $connection.CreateCommand()
            $histCommand.CommandText = $insertHistory
            $histCommand.Transaction = $transaction
            
            [void]$histCommand.Parameters.AddWithValue("@RuleId", $ruleId)
            [void]$histCommand.Parameters.AddWithValue("@RuleName", $Name)
            [void]$histCommand.Parameters.AddWithValue("@ActionDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
            [void]$histCommand.Parameters.AddWithValue("@ActionBy", $env:USERNAME)
            [void]$histCommand.Parameters.AddWithValue("@Details", "Rule created with $($VMs.Count) VMs")
            
            [void]$histCommand.ExecuteNonQuery()
            
            $transaction.Commit()
            
            Write-Host "✓ Added $Type rule: $Name" -ForegroundColor Green
            Write-Host "  VMs: $($VMs -join ', ')" -ForegroundColor Gray
            Write-Host "  Rule ID: $ruleId" -ForegroundColor Gray
            
            return $ruleId
        }
        catch {
            $transaction.Rollback()
            throw
        }
        finally {
            $connection.Close()
        }
    }
    catch {
        Write-Error "Failed to add rule: $($_.Exception.Message)"
        return $false
    }
}

function Get-CustomDRSAffinityRuleDB {
    <#
    .SYNOPSIS
    Gets affinity rules from the database
    
    .DESCRIPTION
    Retrieves affinity rules from the SQLite database with optional filtering
    
    .PARAMETER Name
    Optional rule name to filter by
    
    .PARAMETER Type
    Optional rule type to filter by (Affinity/AntiAffinity)
    
    .PARAMETER ClusterName
    Optional cluster name to filter by
    
    .PARAMETER EnabledOnly
    If specified, only returns enabled rules
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Get-CustomDRSAffinityRuleDB
    
    .EXAMPLE
    Get-CustomDRSAffinityRuleDB -Type AntiAffinity -EnabledOnly
    
    .EXAMPLE
    Get-CustomDRSAffinityRuleDB -ClusterName "Production"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Affinity','AntiAffinity','All')]
        [string]$Type = 'All',
        
        [Parameter(Mandatory=$false)]
        [string]$ClusterName,
        
        [Parameter(Mandatory=$false)]
        [switch]$EnabledOnly,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Build query
        $query = @"
SELECT 
    r.RuleId,
    r.RuleName,
    r.RuleType,
    r.Enabled,
    r.ClusterName,
    r.Description,
    r.CreatedDate,
    r.ModifiedDate,
    r.CreatedBy,
    r.ModifiedBy,
    GROUP_CONCAT(rv.VMName, ',') as VMs
FROM AffinityRules r
LEFT JOIN RuleVMs rv ON r.RuleId = rv.RuleId
WHERE 1=1
"@
        
        if ($Name) {
            $query += " AND r.RuleName = @Name"
        }
        
        if ($Type -ne 'All') {
            $query += " AND r.RuleType = @Type"
        }
        
        if ($ClusterName) {
            $query += " AND r.ClusterName = @ClusterName"
        }
        
        if ($EnabledOnly) {
            $query += " AND r.Enabled = 1"
        }
        
        $query += " GROUP BY r.RuleId ORDER BY r.RuleName;"
        
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        
        if ($Name) {
            [void]$command.Parameters.AddWithValue("@Name", $Name)
        }
        if ($Type -ne 'All') {
            [void]$command.Parameters.AddWithValue("@Type", $Type)
        }
        if ($ClusterName) {
            [void]$command.Parameters.AddWithValue("@ClusterName", $ClusterName)
        }
        
        $reader = $command.ExecuteReader()
        
        $rules = @()
        while ($reader.Read()) {
            $vmList = if ($reader["VMs"] -ne [DBNull]::Value) {
                $reader["VMs"].ToString() -split ','
            } else {
                @()
            }
            
            $rules += [PSCustomObject]@{
                RuleId = $reader["RuleId"]
                Name = $reader["RuleName"]
                Type = $reader["RuleType"]
                Enabled = [bool]$reader["Enabled"]
                ClusterName = if ($reader["ClusterName"] -ne [DBNull]::Value) { $reader["ClusterName"] } else { $null }
                Description = if ($reader["Description"] -ne [DBNull]::Value) { $reader["Description"] } else { $null }
                VMs = $vmList
                VMCount = $vmList.Count
                CreatedDate = $reader["CreatedDate"]
                ModifiedDate = $reader["ModifiedDate"]
                CreatedBy = if ($reader["CreatedBy"] -ne [DBNull]::Value) { $reader["CreatedBy"] } else { $null }
                ModifiedBy = if ($reader["ModifiedBy"] -ne [DBNull]::Value) { $reader["ModifiedBy"] } else { $null }
            }
        }
        
        $reader.Close()
        $connection.Close()
        
        return $rules
    }
    catch {
        Write-Error "Failed to retrieve rules: $($_.Exception.Message)"
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        return @()
    }
}

function Update-CustomDRSAffinityRuleDB {
    <#
    .SYNOPSIS
    Updates an existing affinity rule in the database
    
    .DESCRIPTION
    Modifies an affinity rule's properties or VM membership
    
    .PARAMETER Name
    Name of the rule to update
    
    .PARAMETER NewName
    Optional new name for the rule
    
    .PARAMETER VMs
    Optional new list of VMs (replaces existing)
    
    .PARAMETER AddVMs
    Optional VMs to add to the rule
    
    .PARAMETER RemoveVMs
    Optional VMs to remove from the rule
    
    .PARAMETER Enabled
    Optional enabled state
    
    .PARAMETER Description
    Optional new description
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Update-CustomDRSAffinityRuleDB -Name "DC-AntiAffinity" -AddVMs @("DC04")
    
    .EXAMPLE
    Update-CustomDRSAffinityRuleDB -Name "Old-Rule" -NewName "New-Rule" -Enabled $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$NewName,
        
        [Parameter(Mandatory=$false)]
        [array]$VMs,
        
        [Parameter(Mandatory=$false)]
        [array]$AddVMs,
        
        [Parameter(Mandatory=$false)]
        [array]$RemoveVMs,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled,
        
        [Parameter(Mandatory=$false)]
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        $transaction = $connection.BeginTransaction()
        
        try {
            # Get rule ID
            $getRuleId = "SELECT RuleId FROM AffinityRules WHERE RuleName = @Name;"
            $command = $connection.CreateCommand()
            $command.CommandText = $getRuleId
            $command.Transaction = $transaction
            [void]$command.Parameters.AddWithValue("@Name", $Name)
            
            $ruleId = $command.ExecuteScalar()
            
            if (-not $ruleId) {
                throw "Rule '$Name' not found"
            }
            
            $changes = @()
            
            # Update rule properties
            $updateParts = @()
            $updateCommand = $connection.CreateCommand()
            $updateCommand.Transaction = $transaction
            
            if ($NewName) {
                $updateParts += "RuleName = @NewName"
                [void]$updateCommand.Parameters.AddWithValue("@NewName", $NewName)
                $changes += "Renamed to '$NewName'"
            }
            
            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $updateParts += "Enabled = @Enabled"
                [void]$updateCommand.Parameters.AddWithValue("@Enabled", [int]$Enabled)
                $changes += "Enabled = $Enabled"
            }
            
            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateParts += "Description = @Description"
                [void]$updateCommand.Parameters.AddWithValue("@Description", $Description)
                $changes += "Description updated"
            }
            
            if ($updateParts.Count -gt 0) {
                $updateParts += "ModifiedDate = @ModifiedDate"
                $updateParts += "ModifiedBy = @ModifiedBy"
                
                [void]$updateCommand.Parameters.AddWithValue("@ModifiedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                [void]$updateCommand.Parameters.AddWithValue("@ModifiedBy", $env:USERNAME)
                [void]$updateCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                
                $updateCommand.CommandText = "UPDATE AffinityRules SET $($updateParts -join ', ') WHERE RuleId = @RuleId;"
                [void]$updateCommand.ExecuteNonQuery()
            }
            
            # Handle VM updates
            if ($VMs) {
                # Replace all VMs
                $deleteVMs = "DELETE FROM RuleVMs WHERE RuleId = @RuleId;"
                $delCommand = $connection.CreateCommand()
                $delCommand.CommandText = $deleteVMs
                $delCommand.Transaction = $transaction
                [void]$delCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                [void]$delCommand.ExecuteNonQuery()
                
                $insertVM = "INSERT INTO RuleVMs (RuleId, VMName, AddedDate) VALUES (@RuleId, @VMName, @AddedDate);"
                foreach ($vm in $VMs) {
                    $vmCommand = $connection.CreateCommand()
                    $vmCommand.CommandText = $insertVM
                    $vmCommand.Transaction = $transaction
                    
                    [void]$vmCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                    [void]$vmCommand.Parameters.AddWithValue("@VMName", $vm)
                    [void]$vmCommand.Parameters.AddWithValue("@AddedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                    
                    [void]$vmCommand.ExecuteNonQuery()
                }
                
                $changes += "VM list replaced with $($VMs.Count) VMs"
            }
            
            if ($AddVMs) {
                $insertVM = "INSERT OR IGNORE INTO RuleVMs (RuleId, VMName, AddedDate) VALUES (@RuleId, @VMName, @AddedDate);"
                foreach ($vm in $AddVMs) {
                    $vmCommand = $connection.CreateCommand()
                    $vmCommand.CommandText = $insertVM
                    $vmCommand.Transaction = $transaction
                    
                    [void]$vmCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                    [void]$vmCommand.Parameters.AddWithValue("@VMName", $vm)
                    [void]$vmCommand.Parameters.AddWithValue("@AddedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                    
                    [void]$vmCommand.ExecuteNonQuery()
                }
                
                $changes += "Added $($AddVMs.Count) VM(s)"
            }
            
            if ($RemoveVMs) {
                $deleteVM = "DELETE FROM RuleVMs WHERE RuleId = @RuleId AND VMName = @VMName;"
                foreach ($vm in $RemoveVMs) {
                    $vmCommand = $connection.CreateCommand()
                    $vmCommand.CommandText = $deleteVM
                    $vmCommand.Transaction = $transaction
                    
                    [void]$vmCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                    [void]$vmCommand.Parameters.AddWithValue("@VMName", $vm)
                    
                    [void]$vmCommand.ExecuteNonQuery()
                }
                
                $changes += "Removed $($RemoveVMs.Count) VM(s)"
            }
            
            # Add to history
            if ($changes.Count -gt 0) {
                $insertHistory = @"
INSERT INTO RuleHistory (RuleId, RuleName, Action, ActionDate, ActionBy, Details)
VALUES (@RuleId, @RuleName, 'Updated', @ActionDate, @ActionBy, @Details);
"@
                
                $histCommand = $connection.CreateCommand()
                $histCommand.CommandText = $insertHistory
                $histCommand.Transaction = $transaction
                
                [void]$histCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                [void]$histCommand.Parameters.AddWithValue("@RuleName", $(if ($NewName) { $NewName } else { $Name }))
                [void]$histCommand.Parameters.AddWithValue("@ActionDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                [void]$histCommand.Parameters.AddWithValue("@ActionBy", $env:USERNAME)
                [void]$histCommand.Parameters.AddWithValue("@Details", $changes -join '; ')
                
                [void]$histCommand.ExecuteNonQuery()
            }
            
            $transaction.Commit()
            
            Write-Host "✓ Updated rule: $Name" -ForegroundColor Green
            foreach ($change in $changes) {
                Write-Host "  - $change" -ForegroundColor Gray
            }
            
            return $true
        }
        catch {
            $transaction.Rollback()
            throw
        }
        finally {
            $connection.Close()
        }
    }
    catch {
        Write-Error "Failed to update rule: $($_.Exception.Message)"
        return $false
    }
}

function Remove-CustomDRSAffinityRuleDB {
    <#
    .SYNOPSIS
    Removes an affinity rule from the database
    
    .DESCRIPTION
    Deletes an affinity rule and all associated VMs from the database
    
    .PARAMETER Name
    Name of the rule to remove
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Remove-CustomDRSAffinityRuleDB -Name "Old-Rule"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    if ($PSCmdlet.ShouldProcess($Name, "Remove affinity rule")) {
        try {
            $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
            $transaction = $connection.BeginTransaction()
            
            try {
                # Get rule info for history
                $getRule = "SELECT RuleId FROM AffinityRules WHERE RuleName = @Name;"
                $command = $connection.CreateCommand()
                $command.CommandText = $getRule
                $command.Transaction = $transaction
                [void]$command.Parameters.AddWithValue("@Name", $Name)
                
                $ruleId = $command.ExecuteScalar()
                
                if (-not $ruleId) {
                    throw "Rule '$Name' not found"
                }
                
                # Add to history before deletion
                $insertHistory = @"
INSERT INTO RuleHistory (RuleId, RuleName, Action, ActionDate, ActionBy, Details)
VALUES (@RuleId, @RuleName, 'Deleted', @ActionDate, @ActionBy, @Details);
"@
                
                $histCommand = $connection.CreateCommand()
                $histCommand.CommandText = $insertHistory
                $histCommand.Transaction = $transaction
                
                [void]$histCommand.Parameters.AddWithValue("@RuleId", $ruleId)
                [void]$histCommand.Parameters.AddWithValue("@RuleName", $Name)
                [void]$histCommand.Parameters.AddWithValue("@ActionDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                [void]$histCommand.Parameters.AddWithValue("@ActionBy", $env:USERNAME)
                [void]$histCommand.Parameters.AddWithValue("@Details", "Rule deleted")
                
                [void]$histCommand.ExecuteNonQuery()
                
                # Delete rule (cascade will delete RuleVMs)
                $deleteRule = "DELETE FROM AffinityRules WHERE RuleName = @Name;"
                $delCommand = $connection.CreateCommand()
                $delCommand.CommandText = $deleteRule
                $delCommand.Transaction = $transaction
                [void]$delCommand.Parameters.AddWithValue("@Name", $Name)
                
                [void]$delCommand.ExecuteNonQuery()
                
                $transaction.Commit()
                
                Write-Host "✓ Removed rule: $Name" -ForegroundColor Green
                
                return $true
            }
            catch {
                $transaction.Rollback()
                throw
            }
            finally {
                $connection.Close()
            }
        }
        catch {
            Write-Error "Failed to remove rule: $($_.Exception.Message)"
            return $false
        }
    }
}

#endregion

#region Rule History and Auditing

function Get-CustomDRSRuleHistory {
    <#
    .SYNOPSIS
    Gets the history of changes to affinity rules
    
    .DESCRIPTION
    Retrieves audit trail of all changes made to affinity rules
    
    .PARAMETER Name
    Optional rule name to filter by
    
    .PARAMETER Days
    Number of days of history to retrieve (default: 30)
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Get-CustomDRSRuleHistory -Days 7
    
    .EXAMPLE
    Get-CustomDRSRuleHistory -Name "DC-AntiAffinity"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [int]$Days = 30,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $query = @"
SELECT 
    HistoryId,
    RuleId,
    RuleName,
    Action,
    ActionDate,
    ActionBy,
    Details
FROM RuleHistory
WHERE ActionDate >= datetime('now', '-$Days days')
"@
        
        if ($Name) {
            $query += " AND RuleName = @Name"
        }
        
        $query += " ORDER BY ActionDate DESC;"
        
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        
        if ($Name) {
            [void]$command.Parameters.AddWithValue("@Name", $Name)
        }
        
        $reader = $command.ExecuteReader()
        
        $history = @()
        while ($reader.Read()) {
            $history += [PSCustomObject]@{
                HistoryId = $reader["HistoryId"]
                RuleId = if ($reader["RuleId"] -ne [DBNull]::Value) { $reader["RuleId"] } else { $null }
                RuleName = $reader["RuleName"]
                Action = $reader["Action"]
                ActionDate = $reader["ActionDate"]
                ActionBy = if ($reader["ActionBy"] -ne [DBNull]::Value) { $reader["ActionBy"] } else { $null }
                Details = if ($reader["Details"] -ne [DBNull]::Value) { $reader["Details"] } else { $null }
            }
        }
        
        $reader.Close()
        $connection.Close()
        
        return $history
    }
    catch {
        Write-Error "Failed to retrieve history: $($_.Exception.Message)"
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        return @()
    }
}

function Add-CustomDRSRuleViolation {
    <#
    .SYNOPSIS
    Records a rule violation in the database
    
    .DESCRIPTION
    Logs when an affinity rule is violated (typically detected during load balancing)
    
    .PARAMETER RuleName
    Name of the violated rule
    
    .PARAMETER VMName
    Name of the VM involved in the violation
    
    .PARAMETER HostName
    Name of the host where the violation occurred
    
    .PARAMETER ViolationType
    Type of violation (e.g., "AntiAffinityViolation", "AffinityNotMet")
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Add-CustomDRSRuleViolation -RuleName "DC-AntiAffinity" -VMName "DC01" -HostName "esxi-01" -ViolationType "AntiAffinityViolation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RuleName,
        
        [Parameter(Mandatory=$true)]
        [string]$VMName,
        
        [Parameter(Mandatory=$true)]
        [string]$HostName,
        
        [Parameter(Mandatory=$true)]
        [string]$ViolationType,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Get rule ID
        $getRuleId = "SELECT RuleId FROM AffinityRules WHERE RuleName = @RuleName;"
        $command = $connection.CreateCommand()
        $command.CommandText = $getRuleId
        [void]$command.Parameters.AddWithValue("@RuleName", $RuleName)
        
        $ruleId = $command.ExecuteScalar()
        
        if (-not $ruleId) {
            Write-Warning "Rule '$RuleName' not found, cannot log violation"
            $connection.Close()
            return $false
        }
        
        # Insert violation
        $insertViolation = @"
INSERT INTO RuleViolations (RuleId, RuleName, VMName, HostName, ViolationType, DetectedDate)
VALUES (@RuleId, @RuleName, @VMName, @HostName, @ViolationType, @DetectedDate);
"@
        
        $command.CommandText = $insertViolation
        $command.Parameters.Clear()
        [void]$command.Parameters.AddWithValue("@RuleId", $ruleId)
        [void]$command.Parameters.AddWithValue("@RuleName", $RuleName)
        [void]$command.Parameters.AddWithValue("@VMName", $VMName)
        [void]$command.Parameters.AddWithValue("@HostName", $HostName)
        [void]$command.Parameters.AddWithValue("@ViolationType", $ViolationType)
        [void]$command.Parameters.AddWithValue("@DetectedDate", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
        
        [void]$command.ExecuteNonQuery()
        $connection.Close()
        
        return $true
    }
    catch {
        Write-Error "Failed to log violation: $($_.Exception.Message)"
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        return $false
    }
}

function Get-CustomDRSRuleViolations {
    <#
    .SYNOPSIS
    Gets recorded rule violations
    
    .DESCRIPTION
    Retrieves logged affinity rule violations, optionally filtered
    
    .PARAMETER UnresolvedOnly
    If specified, only returns unresolved violations
    
    .PARAMETER Days
    Number of days of violations to retrieve (default: 30)
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Get-CustomDRSRuleViolations -UnresolvedOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$UnresolvedOnly,
        
        [Parameter(Mandatory=$false)]
        [int]$Days = 30,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $query = @"
SELECT 
    ViolationId,
    RuleId,
    RuleName,
    VMName,
    HostName,
    ViolationType,
    DetectedDate,
    Resolved,
    ResolvedDate
FROM RuleViolations
WHERE DetectedDate >= datetime('now', '-$Days days')
"@
        
        if ($UnresolvedOnly) {
            $query += " AND Resolved = 0"
        }
        
        $query += " ORDER BY DetectedDate DESC;"
        
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        
        $reader = $command.ExecuteReader()
        
        $violations = @()
        while ($reader.Read()) {
            $violations += [PSCustomObject]@{
                ViolationId = $reader["ViolationId"]
                RuleId = $reader["RuleId"]
                RuleName = $reader["RuleName"]
                VMName = $reader["VMName"]
                HostName = $reader["HostName"]
                ViolationType = $reader["ViolationType"]
                DetectedDate = $reader["DetectedDate"]
                Resolved = [bool]$reader["Resolved"]
                ResolvedDate = if ($reader["ResolvedDate"] -ne [DBNull]::Value) { $reader["ResolvedDate"] } else { $null }
            }
        }
        
        $reader.Close()
        $connection.Close()
        
        return $violations
    }
    catch {
        Write-Error "Failed to retrieve violations: $($_.Exception.Message)"
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        return @()
    }
}

#endregion

#region Import/Export

function Export-CustomDRSRules {
    <#
    .SYNOPSIS
    Exports affinity rules to JSON file
    
    .DESCRIPTION
    Exports all or filtered affinity rules to a JSON file for backup or migration
    
    .PARAMETER Path
    Path to the JSON export file
    
    .PARAMETER ClusterName
    Optional cluster name to filter export
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Export-CustomDRSRules -Path "C:\Backup\DRS-Rules.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$false)]
        [string]$ClusterName,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        $rules = if ($ClusterName) {
            Get-CustomDRSAffinityRuleDB -ClusterName $ClusterName -DatabasePath $DatabasePath
        } else {
            Get-CustomDRSAffinityRuleDB -DatabasePath $DatabasePath
        }
        
        $export = @{
            ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ExportedBy = $env:USERNAME
            RuleCount = $rules.Count
            Rules = $rules
        }
        
        $export | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        
        Write-Host "✓ Exported $($rules.Count) rule(s) to: $Path" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Error "Failed to export rules: $($_.Exception.Message)"
        return $false
    }
}

function Import-CustomDRSRules {
    <#
    .SYNOPSIS
    Imports affinity rules from JSON file
    
    .DESCRIPTION
    Imports affinity rules from a JSON export file
    
    .PARAMETER Path
    Path to the JSON import file
    
    .PARAMETER OverwriteExisting
    If specified, overwrites existing rules with same name
    
    .PARAMETER DatabasePath
    Path to the SQLite database file
    
    .EXAMPLE
    Import-CustomDRSRules -Path "C:\Backup\DRS-Rules.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$false)]
        [switch]$OverwriteExisting,
        
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )
    
    try {
        if (-not (Test-Path $Path)) {
            throw "Import file not found: $Path"
        }
        
        $import = Get-Content -Path $Path -Raw | ConvertFrom-Json
        
        Write-Host "Importing $($import.RuleCount) rule(s) from: $Path" -ForegroundColor Yellow
        Write-Host "Export date: $($import.ExportDate)" -ForegroundColor Gray
        
        $imported = 0
        $skipped = 0
        
        foreach ($rule in $import.Rules) {
            # Check if rule exists
            $existing = Get-CustomDRSAffinityRuleDB -Name $rule.Name -DatabasePath $DatabasePath
            
            if ($existing -and -not $OverwriteExisting) {
                Write-Host "  Skipping $($rule.Name) - already exists" -ForegroundColor Yellow
                $skipped++
                continue
            }
            
            if ($existing -and $OverwriteExisting) {
                # Remove existing rule
                Remove-CustomDRSAffinityRuleDB -Name $rule.Name -DatabasePath $DatabasePath -Confirm:$false
            }
            
            # Add rule
            $result = Add-CustomDRSAffinityRuleDB `
                -Name $rule.Name `
                -Type $rule.Type `
                -VMs $rule.VMs `
                -ClusterName $rule.ClusterName `
                -Description $rule.Description `
                -Enabled $rule.Enabled `
                -DatabasePath $DatabasePath
            
            if ($result) {
                $imported++
            }
        }
        
        Write-Host "`n✓ Import complete" -ForegroundColor Green
        Write-Host "  Imported: $imported" -ForegroundColor Gray
        Write-Host "  Skipped: $skipped" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Error "Failed to import rules: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Helper Functions

function Get-ClusterResourceMetrics {
    <#
    .SYNOPSIS
    Gets detailed resource metrics for a cluster
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
    )
    
    $hosts = Get-VMHost -Location $Cluster | Where-Object {$_.ConnectionState -eq 'Connected' -and $_.PowerState -eq 'PoweredOn'}
    
    $metrics = @()
    foreach ($vmHost in $hosts) {
        $vms = Get-VM -Location $vmHost | Where-Object {$_.PowerState -eq 'PoweredOn'}
        
        $cpuUsageMhz = ($vms | Measure-Object -Property UsedCpuMhz -Sum).Sum
        $memUsageGB = ($vms | Measure-Object -Property MemoryGB -Sum).Sum
        
        $metrics += [PSCustomObject]@{
            Host = $vmHost.Name
            HostObject = $vmHost
            CpuTotalMhz = $vmHost.CpuTotalMhz
            CpuUsageMhz = $cpuUsageMhz
            CpuUsagePercent = [math]::Round(($cpuUsageMhz / $vmHost.CpuTotalMhz) * 100, 2)
            MemTotalGB = $vmHost.MemoryTotalGB
            MemUsageGB = $memUsageGB
            MemUsagePercent = [math]::Round(($memUsageGB / $vmHost.MemoryTotalGB) * 100, 2)
            VMCount = $vms.Count
            VMs = $vms
        }
    }
    
    return $metrics
}

function Get-VMResourceUsage {
    <#
    .SYNOPSIS
    Gets resource usage for a VM
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
    )
    
    return [PSCustomObject]@{
        Name = $VM.Name
        VMObject = $VM
        CpuUsageMhz = $VM.ExtensionData.Summary.QuickStats.OverallCpuUsage
        MemUsageGB = $VM.MemoryGB
        NumCpu = $VM.NumCpu
        Host = $VM.VMHost.Name
    }
}

function Test-AffinityRuleCompliance {
    <#
    .SYNOPSIS
    Tests if a VM move would violate affinity/anti-affinity rules
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $VM,
        [Parameter(Mandatory=$true)]
        $TargetHost,
        [Parameter(Mandatory=$true)]
        $AffinityRules
    )
    
    foreach ($rule in $AffinityRules) {
        if ($rule.VMs -contains $VM.Name) {
            if ($rule.Type -eq 'AntiAffinity') {
                # Check if any other VM in the rule is on the target host
                $otherVMs = $rule.VMs | Where-Object {$_ -ne $VM.Name}
                $targetHostVMs = (Get-VM -Location $TargetHost).Name
                
                foreach ($otherVM in $otherVMs) {
                    if ($targetHostVMs -contains $otherVM) {
                        Write-Verbose "Anti-affinity rule violated: $($rule.Name)"
                        return $false
                    }
                }
            }
            elseif ($rule.Type -eq 'Affinity') {
                # Check if all other VMs in the rule are on the target host or will move
                $otherVMs = $rule.VMs | Where-Object {$_ -ne $VM.Name}
                $targetHostVMs = (Get-VM -Location $TargetHost).Name
                
                foreach ($otherVM in $otherVMs) {
                    if ($targetHostVMs -notcontains $otherVM) {
                        Write-Verbose "Affinity rule would not be satisfied: $($rule.Name)"
                        # Note: This is a warning, not a violation, as other VMs might move
                    }
                }
            }
        }
    }
    
    return $true
}

function Calculate-LoadBalanceScore {
    <#
    .SYNOPSIS
    Calculates a load balance score for the cluster (lower is better balanced)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Metrics
    )
    
    $cpuStdDev = ($Metrics | Measure-Object -Property CpuUsagePercent -StandardDeviation).StandardDeviation
    $memStdDev = ($Metrics | Measure-Object -Property MemUsagePercent -StandardDeviation).StandardDeviation
    
    # Combined score (lower is better)
    $score = ($cpuStdDev * 0.5) + ($memStdDev * 0.5)
    
    return [PSCustomObject]@{
        Score = $score
        CpuStdDev = $cpuStdDev
        MemStdDev = $memStdDev
    }
}

#endregion

#region DRS Core Functions

function Invoke-CustomDRSLoadBalance {
    <#
    .SYNOPSIS
    Performs load balancing across cluster hosts similar to VMware DRS
    
    .DESCRIPTION
    Analyzes cluster resource usage and generates VM migration recommendations
    to balance CPU and memory load across ESXi hosts
    
    .PARAMETER Cluster
    The vCenter cluster to balance
    
    .PARAMETER AggressivenessLevel
    DRS aggressiveness level (1-5, default 3)
    1 = Very Conservative (only critical moves)
    5 = Very Aggressive (balance at all costs)
    
    .PARAMETER AutoApply
    If specified, automatically applies migration recommendations
    
    .PARAMETER AffinityRules
    Array of affinity/anti-affinity rules to respect
    
    .EXAMPLE
    Invoke-CustomDRSLoadBalance -Cluster (Get-Cluster "Production") -AggressivenessLevel 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,5)]
        [int]$AggressivenessLevel = 3,
        
        [Parameter(Mandatory=$false)]
        [switch]$AutoApply,
        
        [Parameter(Mandatory=$false)]
        [array]$AffinityRules = @()
    )
    
    Write-Host "`n=== Custom DRS Load Balancing Analysis ===" -ForegroundColor Cyan
    Write-Host "Cluster: $($Cluster.Name)" -ForegroundColor Yellow
    Write-Host "Aggressiveness Level: $AggressivenessLevel" -ForegroundColor Yellow
    
    # Get current cluster metrics
    $metrics = Get-ClusterResourceMetrics -Cluster $Cluster
    
    if ($metrics.Count -lt 2) {
        Write-Warning "Cluster must have at least 2 hosts for load balancing"
        return
    }
    
    # Calculate initial load balance
    $initialScore = Calculate-LoadBalanceScore -Metrics $metrics
    Write-Host "`nInitial Load Balance Score: $([math]::Round($initialScore.Score, 2))" -ForegroundColor White
    Write-Host "  CPU Std Dev: $([math]::Round($initialScore.CpuStdDev, 2))%" -ForegroundColor Gray
    Write-Host "  Mem Std Dev: $([math]::Round($initialScore.MemStdDev, 2))%" -ForegroundColor Gray
    
    # Display current host utilization
    Write-Host "`nCurrent Host Utilization:" -ForegroundColor Cyan
    foreach ($metric in $metrics | Sort-Object CpuUsagePercent -Descending) {
        Write-Host ("  {0,-25} CPU: {1,5:N1}%  Mem: {2,5:N1}%  VMs: {3}" -f $metric.Host, $metric.CpuUsagePercent, $metric.MemUsagePercent, $metric.VMCount) -ForegroundColor White
    }
    
    # Define thresholds based on aggressiveness
    $thresholds = @{
        1 = @{CpuDiff = 40; MemDiff = 40; MinImprovement = 10}  # Conservative
        2 = @{CpuDiff = 30; MemDiff = 30; MinImprovement = 7}
        3 = @{CpuDiff = 20; MemDiff = 20; MinImprovement = 5}   # Normal
        4 = @{CpuDiff = 15; MemDiff = 15; MinImprovement = 3}
        5 = @{CpuDiff = 10; MemDiff = 10; MinImprovement = 2}   # Aggressive
    }
    
    $threshold = $thresholds[$AggressivenessLevel]
    
    # Find migration candidates
    $migrations = @()
    $maxIterations = 10
    $iteration = 0
    
    while ($iteration -lt $maxIterations) {
        $iteration++
        
        # Find most loaded and least loaded hosts
        $sortedByCpu = $metrics | Sort-Object CpuUsagePercent -Descending
        $sortedByMem = $metrics | Sort-Object MemUsagePercent -Descending
        
        # Determine if CPU or Memory is the primary constraint
        $cpuImbalance = $sortedByCpu[0].CpuUsagePercent - $sortedByCpu[-1].CpuUsagePercent
        $memImbalance = $sortedByMem[0].MemUsagePercent - $sortedByMem[-1].MemUsagePercent
        
        if ($cpuImbalance -lt $threshold.CpuDiff -and $memImbalance -lt $threshold.MemDiff) {
            Write-Verbose "Cluster is balanced within threshold (CPU diff: $cpuImbalance%, Mem diff: $memImbalance%)"
            break
        }
        
        # Focus on the resource with greater imbalance
        if ($cpuImbalance -ge $memImbalance) {
            $sourceHost = $sortedByCpu[0]
            $targetHost = $sortedByCpu[-1]
            $resourceType = "CPU"
        } else {
            $sourceHost = $sortedByMem[0]
            $targetHost = $sortedByMem[-1]
            $resourceType = "Memory"
        }
        
        Write-Verbose "Iteration $iteration : Attempting to balance $resourceType"
        Write-Verbose "  Source: $($sourceHost.Host) - CPU: $($sourceHost.CpuUsagePercent)%, Mem: $($sourceHost.MemUsagePercent)%"
        Write-Verbose "  Target: $($targetHost.Host) - CPU: $($targetHost.CpuUsagePercent)%, Mem: $($targetHost.MemUsagePercent)%"
        
        # Find best VM to migrate
        $bestVM = $null
        $bestScore = 0
        
        foreach ($vm in $sourceHost.VMs) {
            $vmMetrics = Get-VMResourceUsage -VM $vm
            
            # Skip if VM doesn't have metrics
            if ($null -eq $vmMetrics.CpuUsageMhz -or $vmMetrics.CpuUsageMhz -eq 0) {
                continue
            }
            
            # Calculate impact
            $vmCpuPercent = ($vmMetrics.CpuUsageMhz / $sourceHost.CpuTotalMhz) * 100
            $vmMemPercent = ($vmMetrics.MemUsageGB / $sourceHost.MemTotalGB) * 100
            
            # Check if migration would help
            $sourceCpuAfter = $sourceHost.CpuUsagePercent - $vmCpuPercent
            $targetCpuAfter = $targetHost.CpuUsagePercent + ($vmMetrics.CpuUsageMhz / $targetHost.CpuTotalMhz) * 100
            
            $sourceMemAfter = $sourceHost.MemUsagePercent - $vmMemPercent
            $targetMemAfter = $targetHost.MemUsagePercent + ($vmMetrics.MemUsageGB / $targetHost.MemTotalGB) * 100
            
            # Check if target would become overloaded
            if ($targetCpuAfter -gt 90 -or $targetMemAfter -gt 90) {
                continue
            }
            
            # Check affinity rules
            if ($AffinityRules.Count -gt 0) {
                if (-not (Test-AffinityRuleCompliance -VM $vm -TargetHost $targetHost.HostObject -AffinityRules $AffinityRules)) {
                    Write-Verbose "  Skipping $($vm.Name) - would violate affinity rules"
                    continue
                }
            }
            
            # Calculate improvement score
            $cpuImprovement = [math]::Abs($sourceCpuAfter - $targetCpuAfter) - [math]::Abs($sourceHost.CpuUsagePercent - $targetHost.CpuUsagePercent)
            $memImprovement = [math]::Abs($sourceMemAfter - $targetMemAfter) - [math]::Abs($sourceHost.MemUsagePercent - $targetHost.MemUsagePercent)
            $improvementScore = ($cpuImprovement + $memImprovement) / 2
            
            if ($improvementScore -gt $bestScore -and $improvementScore -gt $threshold.MinImprovement) {
                $bestScore = $improvementScore
                $bestVM = @{
                    VM = $vm
                    Metrics = $vmMetrics
                    SourceHost = $sourceHost
                    TargetHost = $targetHost
                    ImprovementScore = $improvementScore
                    ResourceType = $resourceType
                }
            }
        }
        
        if ($null -eq $bestVM) {
            Write-Verbose "No suitable VM found for migration in iteration $iteration"
            break
        }
        
        # Add migration recommendation
        $migrations += [PSCustomObject]@{
            VM = $bestVM.VM.Name
            VMObject = $bestVM.VM
            SourceHost = $bestVM.SourceHost.Host
            TargetHost = $bestVM.TargetHost.Host
            TargetHostObject = $bestVM.TargetHost.HostObject
            CpuUsageMhz = $bestVM.Metrics.CpuUsageMhz
            MemUsageGB = $bestVM.Metrics.MemUsageGB
            ImprovementScore = [math]::Round($bestVM.ImprovementScore, 2)
            ResourceType = $bestVM.ResourceType
            Priority = if ($bestScore -gt 15) {"High"} elseif ($bestScore -gt 8) {"Medium"} else {"Low"}
        }
        
        # Update metrics for next iteration
        $vmCpuMhz = $bestVM.Metrics.CpuUsageMhz
        $vmMemGB = $bestVM.Metrics.MemUsageGB
        
        ($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).CpuUsageMhz -= $vmCpuMhz
        ($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).MemUsageGB -= $vmMemGB
        ($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).CpuUsagePercent = 
            [math]::Round((($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).CpuUsageMhz / $bestVM.SourceHost.CpuTotalMhz) * 100, 2)
        ($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).MemUsagePercent = 
            [math]::Round((($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).MemUsageGB / $bestVM.SourceHost.MemTotalGB) * 100, 2)
        
        ($metrics | Where-Object {$_.Host -eq $bestVM.TargetHost.Host}).CpuUsageMhz += $vmCpuMhz
        ($metrics | Where-Object {$_.Host -eq $bestVM.TargetHost.Host}).MemUsageGB += $vmMemGB
        ($metrics | Where-Object {$_.Host -eq $bestVM.TargetHost.Host}).CpuUsagePercent = 
            [math]::Round((($metrics | Where-Object {$_.Host -eq $bestVM.TargetHost.Host}).CpuUsageMhz / $bestVM.TargetHost.CpuTotalMhz) * 100, 2)
        ($metrics | Where-Object {$_.Host -eq $bestVM.TargetHost.Host}).MemUsagePercent = 
            [math]::Round((($metrics | Where-Object {$_.Host -eq $bestVM.TargetHost.Host}).MemUsageGB / $bestVM.TargetHost.MemTotalGB) * 100, 2)
        
        # Remove VM from source host's VM list
        ($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).VMs = 
            ($metrics | Where-Object {$_.Host -eq $bestVM.SourceHost.Host}).VMs | Where-Object {$_.Name -ne $bestVM.VM.Name}
    }
    
    # Display recommendations
    if ($migrations.Count -eq 0) {
        Write-Host "`nNo migrations recommended. Cluster is balanced." -ForegroundColor Green
        return
    }
    
    Write-Host "`n=== Migration Recommendations ===" -ForegroundColor Cyan
    Write-Host "Total Recommendations: $($migrations.Count)" -ForegroundColor Yellow
    
    foreach ($mig in $migrations | Sort-Object ImprovementScore -Descending) {
        $color = switch ($mig.Priority) {
            "High" { "Red" }
            "Medium" { "Yellow" }
            "Low" { "White" }
        }
        
        Write-Host "`n[$($mig.Priority)] $($mig.VM)" -ForegroundColor $color
        Write-Host "  From: $($mig.SourceHost) → To: $($mig.TargetHost)" -ForegroundColor Gray
        Write-Host "  Resource: $($mig.ResourceType) | Improvement: $($mig.ImprovementScore)" -ForegroundColor Gray
        Write-Host "  CPU: $($mig.CpuUsageMhz) MHz | Memory: $([math]::Round($mig.MemUsageGB, 2)) GB" -ForegroundColor Gray
    }
    
    # Calculate projected improvement
    $projectedScore = Calculate-LoadBalanceScore -Metrics $metrics
    $improvement = $initialScore.Score - $projectedScore.Score
    $improvementPercent = [math]::Round(($improvement / $initialScore.Score) * 100, 2)
    
    Write-Host "`nProjected Load Balance Score: $([math]::Round($projectedScore.Score, 2))" -ForegroundColor Green
    Write-Host "Improvement: $([math]::Round($improvement, 2)) ($improvementPercent%)" -ForegroundColor Green
    
    # Auto-apply migrations if requested
    if ($AutoApply) {
        Write-Host "`n=== Applying Migrations ===" -ForegroundColor Cyan
        
        $successCount = 0
        $failCount = 0
        
        foreach ($mig in $migrations | Sort-Object ImprovementScore -Descending) {
            try {
                Write-Host "Migrating $($mig.VM) to $($mig.TargetHost)..." -ForegroundColor Yellow -NoNewline
                
                Move-VM -VM $mig.VMObject -Destination $mig.TargetHostObject -Confirm:$false -ErrorAction Stop | Out-Null
                
                Write-Host " Success" -ForegroundColor Green
                $successCount++
                
                # Small delay between migrations to avoid overwhelming vCenter
                Start-Sleep -Seconds 2
            }
            catch {
                Write-Host " Failed: $($_.Exception.Message)" -ForegroundColor Red
                $failCount++
            }
        }
        
        Write-Host "`nMigration Summary: $successCount succeeded, $failCount failed" -ForegroundColor Cyan
    }
    
    return $migrations
}

function Invoke-CustomDRSVMPlacement {
    <#
    .SYNOPSIS
    Determines optimal host placement for a new VM (initial placement)
    
    .DESCRIPTION
    Analyzes cluster resources and affinity rules to recommend the best host
    for placing a new VM, similar to DRS initial placement
    
    .PARAMETER Cluster
    The vCenter cluster for VM placement
    
    .PARAMETER VM
    The VM object to place (can be powered off)
    
    .PARAMETER RequiredCpuMhz
    Required CPU resources in MHz
    
    .PARAMETER RequiredMemoryGB
    Required memory in GB
    
    .PARAMETER AffinityRules
    Array of affinity/anti-affinity rules to respect
    
    .PARAMETER AutoApply
    If specified, automatically migrates the VM to the recommended host
    
    .EXAMPLE
    Invoke-CustomDRSVMPlacement -Cluster (Get-Cluster "Production") -VM (Get-VM "NewVM01") -RequiredCpuMhz 2000 -RequiredMemoryGB 4
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,
        
        [Parameter(Mandatory=$false)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        
        [Parameter(Mandatory=$false)]
        [int]$RequiredCpuMhz = 1000,
        
        [Parameter(Mandatory=$false)]
        [int]$RequiredMemoryGB = 2,
        
        [Parameter(Mandatory=$false)]
        [array]$AffinityRules = @(),
        
        [Parameter(Mandatory=$false)]
        [switch]$AutoApply
    )
    
    Write-Host "`n=== Custom DRS VM Placement Analysis ===" -ForegroundColor Cyan
    Write-Host "Cluster: $($Cluster.Name)" -ForegroundColor Yellow
    
    if ($VM) {
        Write-Host "VM: $($VM.Name)" -ForegroundColor Yellow
        $RequiredCpuMhz = $VM.ExtensionData.Summary.QuickStats.OverallCpuUsage
        $RequiredMemoryGB = $VM.MemoryGB
    }
    
    Write-Host "Required CPU: $RequiredCpuMhz MHz" -ForegroundColor Yellow
    Write-Host "Required Memory: $RequiredMemoryGB GB" -ForegroundColor Yellow
    
    # Get cluster metrics
    $metrics = Get-ClusterResourceMetrics -Cluster $Cluster
    
    # Score each host
    $hostScores = @()
    
    foreach ($metric in $metrics) {
        # Check if host has enough resources
        $availableCpuMhz = $metric.CpuTotalMhz - $metric.CpuUsageMhz
        $availableMemGB = $metric.MemTotalGB - $metric.MemUsageGB
        
        if ($availableCpuMhz -lt $RequiredCpuMhz -or $availableMemGB -lt $RequiredMemoryGB) {
            Write-Verbose "Host $($metric.Host) has insufficient resources"
            continue
        }
        
        # Check affinity rules if VM is provided
        if ($VM -and $AffinityRules.Count -gt 0) {
            if (-not (Test-AffinityRuleCompliance -VM $VM -TargetHost $metric.HostObject -AffinityRules $AffinityRules)) {
                Write-Verbose "Host $($metric.Host) violates affinity rules"
                continue
            }
        }
        
        # Calculate projected utilization
        $projectedCpuPercent = (($metric.CpuUsageMhz + $RequiredCpuMhz) / $metric.CpuTotalMhz) * 100
        $projectedMemPercent = (($metric.MemUsageGB + $RequiredMemoryGB) / $metric.MemTotalGB) * 100
        
        # Score based on load balancing (prefer less loaded hosts)
        # Lower score is better
        $loadScore = ($projectedCpuPercent + $projectedMemPercent) / 2
        
        # Penalty for uneven resource usage
        $balancePenalty = [math]::Abs($projectedCpuPercent - $projectedMemPercent) * 0.1
        
        $totalScore = $loadScore + $balancePenalty
        
        $hostScores += [PSCustomObject]@{
            Host = $metric.Host
            HostObject = $metric.HostObject
            CurrentCpuPercent = $metric.CpuUsagePercent
            CurrentMemPercent = $metric.MemUsagePercent
            ProjectedCpuPercent = [math]::Round($projectedCpuPercent, 2)
            ProjectedMemPercent = [math]::Round($projectedMemPercent, 2)
            Score = [math]::Round($totalScore, 2)
            AvailableCpuMhz = $availableCpuMhz
            AvailableMemGB = [math]::Round($availableMemGB, 2)
        }
    }
    
    if ($hostScores.Count -eq 0) {
        Write-Warning "No suitable hosts found for VM placement"
        return
    }
    
    # Sort by score (best first)
    $hostScores = $hostScores | Sort-Object Score
    
    Write-Host "`n=== Host Placement Recommendations ===" -ForegroundColor Cyan
    
    $rank = 1
    foreach ($host in $hostScores) {
        $color = if ($rank -eq 1) {"Green"} elseif ($rank -eq 2) {"Yellow"} else {"White"}
        
        Write-Host "`n[$rank] $($host.Host)" -ForegroundColor $color
        Write-Host "  Score: $($host.Score) (lower is better)" -ForegroundColor Gray
        Write-Host "  Current: CPU $($host.CurrentCpuPercent)%, Memory $($host.CurrentMemPercent)%" -ForegroundColor Gray
        Write-Host "  Projected: CPU $($host.ProjectedCpuPercent)%, Memory $($host.ProjectedMemPercent)%" -ForegroundColor Gray
        Write-Host "  Available: CPU $($host.AvailableCpuMhz) MHz, Memory $($host.AvailableMemGB) GB" -ForegroundColor Gray
        
        $rank++
    }
    
    $recommendedHost = $hostScores[0]
    Write-Host "`nRecommended Host: $($recommendedHost.Host)" -ForegroundColor Green -BackgroundColor Black
    
    # Auto-apply if requested
    if ($AutoApply -and $VM) {
        try {
            Write-Host "`nMigrating $($VM.Name) to $($recommendedHost.Host)..." -ForegroundColor Yellow
            Move-VM -VM $VM -Destination $recommendedHost.HostObject -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "Migration successful" -ForegroundColor Green
        }
        catch {
            Write-Host "Migration failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return $hostScores
}

function New-CustomDRSAffinityRule {
    <#
    .SYNOPSIS
    Creates an affinity or anti-affinity rule for DRS operations
    
    .DESCRIPTION
    Defines VM-to-VM affinity rules that will be respected during load balancing
    and initial placement operations
    
    .PARAMETER Name
    Name of the affinity rule
    
    .PARAMETER Type
    Type of rule: 'Affinity' (VMs should be together) or 'AntiAffinity' (VMs should be separated)
    
    .PARAMETER VMs
    Array of VM names that are part of this rule
    
    .PARAMETER Enabled
    Whether the rule is enabled (default: $true)
    
    .EXAMPLE
    New-CustomDRSAffinityRule -Name "WebServers-Together" -Type Affinity -VMs @("Web01", "Web02", "Web03")
    
    .EXAMPLE
    New-CustomDRSAffinityRule -Name "DomainControllers-Separate" -Type AntiAffinity -VMs @("DC01", "DC02")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Affinity','AntiAffinity')]
        [string]$Type,
        
        [Parameter(Mandatory=$true)]
        [array]$VMs,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled = $true
    )
    
    if ($VMs.Count -lt 2) {
        Write-Error "Affinity rules require at least 2 VMs"
        return
    }
    
    $rule = [PSCustomObject]@{
        Name = $Name
        Type = $Type
        VMs = $VMs
        Enabled = $Enabled
        Created = Get-Date
    }
    
    Write-Host "Created $Type rule: $Name" -ForegroundColor Green
    Write-Host "  VMs: $($VMs -join ', ')" -ForegroundColor Gray
    
    return $rule
}

function Get-CustomDRSRecommendations {
    <#
    .SYNOPSIS
    Gets current DRS recommendations without applying them
    
    .DESCRIPTION
    Analyzes the cluster and returns migration recommendations that would
    improve load balance, similar to viewing DRS recommendations in vCenter
    
    .PARAMETER Cluster
    The vCenter cluster to analyze
    
    .PARAMETER AggressivenessLevel
    DRS aggressiveness level (1-5, default 3)
    
    .PARAMETER AffinityRules
    Array of affinity/anti-affinity rules to respect
    
    .EXAMPLE
    Get-CustomDRSRecommendations -Cluster (Get-Cluster "Production") | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,5)]
        [int]$AggressivenessLevel = 3,
        
        [Parameter(Mandatory=$false)]
        [array]$AffinityRules = @()
    )
    
    return Invoke-CustomDRSLoadBalance -Cluster $Cluster -AggressivenessLevel $AggressivenessLevel -AffinityRules $AffinityRules
}

function Enable-CustomDRSAutoBalance {
    <#
    .SYNOPSIS
    Enables continuous automatic load balancing (like DRS automation)
    
    .DESCRIPTION
    Continuously monitors cluster balance and automatically applies migrations
    when imbalance exceeds threshold. Runs until stopped with Ctrl+C.
    
    .PARAMETER Cluster
    The vCenter cluster to monitor
    
    .PARAMETER CheckIntervalMinutes
    How often to check for imbalance (default: 5 minutes)
    
    .PARAMETER AggressivenessLevel
    DRS aggressiveness level (1-5, default 3)
    
    .PARAMETER AffinityRules
    Array of affinity/anti-affinity rules to respect
    
    .EXAMPLE
    Enable-CustomDRSAutoBalance -Cluster (Get-Cluster "Production") -CheckIntervalMinutes 10 -AggressivenessLevel 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,
        
        [Parameter(Mandatory=$false)]
        [int]$CheckIntervalMinutes = 5,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,5)]
        [int]$AggressivenessLevel = 3,
        
        [Parameter(Mandatory=$false)]
        [array]$AffinityRules = @()
    )
    
    Write-Host "=== Custom DRS Auto-Balance Enabled ===" -ForegroundColor Green
    Write-Host "Cluster: $($Cluster.Name)" -ForegroundColor Yellow
    Write-Host "Check Interval: $CheckIntervalMinutes minutes" -ForegroundColor Yellow
    Write-Host "Aggressiveness: $AggressivenessLevel" -ForegroundColor Yellow
    Write-Host "`nPress Ctrl+C to stop...`n" -ForegroundColor Cyan
    
    $iteration = 0
    
    while ($true) {
        $iteration++
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        Write-Host "[$timestamp] Check #$iteration" -ForegroundColor Gray
        
        try {
            $recommendations = Invoke-CustomDRSLoadBalance -Cluster $Cluster -AggressivenessLevel $AggressivenessLevel -AffinityRules $AffinityRules -AutoApply
            
            if ($null -eq $recommendations -or $recommendations.Count -eq 0) {
                Write-Host "  No migrations needed - cluster is balanced" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  Error during balancing: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "  Next check in $CheckIntervalMinutes minutes...`n" -ForegroundColor Gray
        Start-Sleep -Seconds ($CheckIntervalMinutes * 60)
    }
}

function Get-CustomDRSClusterHealth {
    <#
    .SYNOPSIS
    Gets comprehensive cluster health and balance metrics
    
    .DESCRIPTION
    Provides detailed health report including resource usage, balance scores,
    and potential issues
    
    .PARAMETER Cluster
    The vCenter cluster to analyze
    
    .EXAMPLE
    Get-CustomDRSClusterHealth -Cluster (Get-Cluster "Production")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
    )
    
    Write-Host "`n=== Custom DRS Cluster Health Report ===" -ForegroundColor Cyan
    Write-Host "Cluster: $($Cluster.Name)" -ForegroundColor Yellow
    Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
    
    # Get metrics
    $metrics = Get-ClusterResourceMetrics -Cluster $Cluster
    $balance = Calculate-LoadBalanceScore -Metrics $metrics
    
    # Cluster totals
    $totalCpuMhz = ($metrics | Measure-Object -Property CpuTotalMhz -Sum).Sum
    $usedCpuMhz = ($metrics | Measure-Object -Property CpuUsageMhz -Sum).Sum
    $totalMemGB = ($metrics | Measure-Object -Property MemTotalGB -Sum).Sum
    $usedMemGB = ($metrics | Measure-Object -Property MemUsageGB -Sum).Sum
    $totalVMs = ($metrics | Measure-Object -Property VMCount -Sum).Sum
    
    Write-Host "`n--- Cluster Summary ---" -ForegroundColor Cyan
    Write-Host "Hosts: $($metrics.Count)" -ForegroundColor White
    Write-Host "Total VMs: $totalVMs" -ForegroundColor White
    Write-Host "Total CPU: $([math]::Round($totalCpuMhz / 1000, 2)) GHz" -ForegroundColor White
    Write-Host "Used CPU: $([math]::Round($usedCpuMhz / 1000, 2)) GHz ($([math]::Round(($usedCpuMhz / $totalCpuMhz) * 100, 2))%)" -ForegroundColor White
    Write-Host "Total Memory: $([math]::Round($totalMemGB, 2)) GB" -ForegroundColor White
    Write-Host "Used Memory: $([math]::Round($usedMemGB, 2)) GB ($([math]::Round(($usedMemGB / $totalMemGB) * 100, 2))%)" -ForegroundColor White
    
    Write-Host "`n--- Load Balance ---" -ForegroundColor Cyan
    Write-Host "Balance Score: $([math]::Round($balance.Score, 2))" -ForegroundColor White
    
    $balanceRating = if ($balance.Score -lt 5) {"Excellent"} 
                     elseif ($balance.Score -lt 10) {"Good"} 
                     elseif ($balance.Score -lt 20) {"Fair"} 
                     else {"Poor"}
    
    $ratingColor = switch ($balanceRating) {
        "Excellent" {"Green"}
        "Good" {"Green"}
        "Fair" {"Yellow"}
        "Poor" {"Red"}
    }
    
    Write-Host "Balance Rating: $balanceRating" -ForegroundColor $ratingColor
    Write-Host "CPU Std Dev: $([math]::Round($balance.CpuStdDev, 2))%" -ForegroundColor White
    Write-Host "Memory Std Dev: $([math]::Round($balance.MemStdDev, 2))%" -ForegroundColor White
    
    Write-Host "`n--- Host Details ---" -ForegroundColor Cyan
    foreach ($metric in $metrics | Sort-Object CpuUsagePercent -Descending) {
        $cpuColor = if ($metric.CpuUsagePercent -gt 80) {"Red"} elseif ($metric.CpuUsagePercent -gt 60) {"Yellow"} else {"Green"}
        $memColor = if ($metric.MemUsagePercent -gt 80) {"Red"} elseif ($metric.MemUsagePercent -gt 60) {"Yellow"} else {"Green"}
        
        Write-Host "`n$($metric.Host)" -ForegroundColor White
        Write-Host "  VMs: $($metric.VMCount)" -ForegroundColor Gray
        Write-Host "  CPU: $([math]::Round($metric.CpuUsageMhz / 1000, 2)) / $([math]::Round($metric.CpuTotalMhz / 1000, 2)) GHz " -NoNewline -ForegroundColor Gray
        Write-Host "($($metric.CpuUsagePercent)%)" -ForegroundColor $cpuColor
        Write-Host "  Memory: $([math]::Round($metric.MemUsageGB, 2)) / $([math]::Round($metric.MemTotalGB, 2)) GB " -NoNewline -ForegroundColor Gray
        Write-Host "($($metric.MemUsagePercent)%)" -ForegroundColor $memColor
    }
    
    # Identify issues
    Write-Host "`n--- Potential Issues ---" -ForegroundColor Cyan
    $issues = @()
    
    $overloadedHosts = $metrics | Where-Object {$_.CpuUsagePercent -gt 80 -or $_.MemUsagePercent -gt 80}
    if ($overloadedHosts) {
        $issues += "⚠ $($overloadedHosts.Count) host(s) with high utilization (>80%)"
    }
    
    if ($balance.Score -gt 20) {
        $issues += "⚠ Cluster is poorly balanced (Score: $([math]::Round($balance.Score, 2)))"
    }
    
    $cpuImbalance = ($metrics | Measure-Object -Property CpuUsagePercent -Maximum).Maximum - 
                     ($metrics | Measure-Object -Property CpuUsagePercent -Minimum).Minimum
    if ($cpuImbalance -gt 30) {
        $issues += "⚠ High CPU imbalance between hosts ($([math]::Round($cpuImbalance, 2))% difference)"
    }
    
    $memImbalance = ($metrics | Measure-Object -Property MemUsagePercent -Maximum).Maximum - 
                     ($metrics | Measure-Object -Property MemUsagePercent -Minimum).Minimum
    if ($memImbalance -gt 30) {
        $issues += "⚠ High Memory imbalance between hosts ($([math]::Round($memImbalance, 2))% difference)"
    }
    
    if ($issues.Count -eq 0) {
        Write-Host "✓ No issues detected - cluster is healthy" -ForegroundColor Green
    }
    else {
        foreach ($issue in $issues) {
            Write-Host $issue -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
}

#endregion

#region Power Management Functions

function Invoke-CustomDPM {
    <#
    .SYNOPSIS
    Implements Distributed Power Management (DPM) - powers off/on hosts based on load
    
    .DESCRIPTION
    Monitors cluster utilization and recommends powering off underutilized hosts
    or powering on hosts when capacity is needed (DPM functionality)
    
    .PARAMETER Cluster
    The vCenter cluster to analyze
    
    .PARAMETER TargetUtilization
    Target average cluster CPU utilization percentage (default: 70)
    
    .PARAMETER MinimumHosts
    Minimum number of hosts to keep powered on (default: 2)
    
    .PARAMETER AutoApply
    If specified, automatically applies power recommendations
    
    .EXAMPLE
    Invoke-CustomDPM -Cluster (Get-Cluster "Production") -TargetUtilization 70 -MinimumHosts 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(30,90)]
        [int]$TargetUtilization = 70,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,10)]
        [int]$MinimumHosts = 2,
        
        [Parameter(Mandatory=$false)]
        [switch]$AutoApply
    )
    
    Write-Host "`n=== Custom DPM (Distributed Power Management) ===" -ForegroundColor Cyan
    Write-Host "Cluster: $($Cluster.Name)" -ForegroundColor Yellow
    Write-Host "Target Utilization: $TargetUtilization%" -ForegroundColor Yellow
    Write-Host "Minimum Hosts: $MinimumHosts" -ForegroundColor Yellow
    
    $metrics = Get-ClusterResourceMetrics -Cluster $Cluster
    
    $avgCpuUtil = ($metrics | Measure-Object -Property CpuUsagePercent -Average).Average
    $avgMemUtil = ($metrics | Measure-Object -Property MemUsagePercent -Average).Average
    $avgUtil = ($avgCpuUtil + $avgMemUtil) / 2
    
    Write-Host "`nCurrent Average Utilization:" -ForegroundColor Cyan
    Write-Host "  CPU: $([math]::Round($avgCpuUtil, 2))%" -ForegroundColor White
    Write-Host "  Memory: $([math]::Round($avgMemUtil, 2))%" -ForegroundColor White
    Write-Host "  Combined: $([math]::Round($avgUtil, 2))%" -ForegroundColor White
    
    $recommendation = $null
    
    # Check if we should power off a host
    if ($avgUtil -lt ($TargetUtilization - 15) -and $metrics.Count -gt $MinimumHosts) {
        # Find least loaded host with fewest VMs
        $candidateHost = $metrics | Sort-Object VMCount, CpuUsagePercent | Select-Object -First 1
        
        if ($candidateHost.VMCount -eq 0) {
            $recommendation = [PSCustomObject]@{
                Action = "PowerOff"
                Host = $candidateHost.Host
                HostObject = $candidateHost.HostObject
                Reason = "Host has no VMs and cluster utilization is low ($([math]::Round($avgUtil, 2))%)"
                CurrentVMs = 0
            }
        }
        elseif ($candidateHost.VMCount -le 3 -and ($metrics.Count - 1) -ge $MinimumHosts) {
            # Check if VMs can be evacuated
            $otherHosts = $metrics | Where-Object {$_.Host -ne $candidateHost.Host}
            $canEvacuate = $true
            
            foreach ($vm in $candidateHost.VMs) {
                $vmCpu = $vm.ExtensionData.Summary.QuickStats.OverallCpuUsage
                $vmMem = $vm.MemoryGB
                
                $suitableHost = $otherHosts | Where-Object {
                    ($_.CpuTotalMhz - $_.CpuUsageMhz) -gt $vmCpu -and
                    ($_.MemTotalGB - $_.MemUsageGB) -gt $vmMem
                } | Select-Object -First 1
                
                if (-not $suitableHost) {
                    $canEvacuate = $false
                    break
                }
            }
            
            if ($canEvacuate) {
                $recommendation = [PSCustomObject]@{
                    Action = "PowerOff"
                    Host = $candidateHost.Host
                    HostObject = $candidateHost.HostObject
                    Reason = "Host has few VMs ($($candidateHost.VMCount)) that can be evacuated, cluster utilization is low"
                    CurrentVMs = $candidateHost.VMCount
                }
            }
        }
    }
    # Check if we should power on a host
    elseif ($avgUtil -gt ($TargetUtilization + 10)) {
        $standbyHosts = Get-VMHost -Location $Cluster | Where-Object {
            $_.ConnectionState -eq 'Maintenance' -or $_.PowerState -eq 'PoweredOff'
        }
        
        if ($standbyHosts) {
            $recommendation = [PSCustomObject]@{
                Action = "PowerOn"
                Host = $standbyHosts[0].Name
                HostObject = $standbyHosts[0]
                Reason = "Cluster utilization is high ($([math]::Round($avgUtil, 2))%) and standby host available"
                CurrentVMs = 0
            }
        }
    }
    
    if ($null -eq $recommendation) {
        Write-Host "`nNo power management actions recommended" -ForegroundColor Green
        Write-Host "Cluster utilization is within acceptable range" -ForegroundColor Gray
        return
    }
    
    # Display recommendation
    Write-Host "`n=== Power Management Recommendation ===" -ForegroundColor Cyan
    
    $actionColor = if ($recommendation.Action -eq "PowerOff") {"Yellow"} else {"Green"}
    Write-Host "`nAction: $($recommendation.Action)" -ForegroundColor $actionColor
    Write-Host "Host: $($recommendation.Host)" -ForegroundColor White
    Write-Host "Reason: $($recommendation.Reason)" -ForegroundColor Gray
    
    if ($recommendation.CurrentVMs -gt 0) {
        Write-Host "Current VMs: $($recommendation.CurrentVMs) (will be evacuated)" -ForegroundColor Gray
    }
    
    # Auto-apply if requested
    if ($AutoApply) {
        Write-Host "`nApplying recommendation..." -ForegroundColor Yellow
        
        try {
            if ($recommendation.Action -eq "PowerOff") {
                # Evacuate VMs if needed
                if ($recommendation.CurrentVMs -gt 0) {
                    Write-Host "Evacuating VMs from $($recommendation.Host)..." -ForegroundColor Yellow
                    $vmsToMove = Get-VM -Location $recommendation.HostObject
                    
                    foreach ($vm in $vmsToMove) {
                        $targetHosts = Get-VMHost -Location $Cluster | Where-Object {
                            $_.Name -ne $recommendation.Host -and
                            $_.ConnectionState -eq 'Connected' -and
                            $_.PowerState -eq 'PoweredOn'
                        }
                        
                        if ($targetHosts) {
                            Write-Host "  Moving $($vm.Name)..." -ForegroundColor Gray
                            Move-VM -VM $vm -Destination $targetHosts[0] -Confirm:$false | Out-Null
                        }
                    }
                }
                
                Write-Host "Entering maintenance mode..." -ForegroundColor Yellow
                Set-VMHost -VMHost $recommendation.HostObject -State Maintenance -Confirm:$false | Out-Null
                
                Write-Host "Powering off host..." -ForegroundColor Yellow
                Stop-VMHost -VMHost $recommendation.HostObject -Confirm:$false | Out-Null
                
                Write-Host "Host powered off successfully" -ForegroundColor Green
            }
            elseif ($recommendation.Action -eq "PowerOn") {
                Write-Host "Powering on host..." -ForegroundColor Yellow
                Start-VMHost -VMHost $recommendation.HostObject -Confirm:$false | Out-Null
                
                Write-Host "Exiting maintenance mode..." -ForegroundColor Yellow
                Set-VMHost -VMHost $recommendation.HostObject -State Connected -Confirm:$false | Out-Null
                
                Write-Host "Host powered on successfully" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Failed to apply recommendation: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return $recommendation
}

#endregion
<#
.SYNOPSIS
Examples demonstrating CustomDRS with SQLite database integration

.DESCRIPTION
Shows how to use the database-backed affinity rule system alongside
the main CustomDRS load balancing functions
#>
#region Extra Functions
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

function Show-RuleManagementMenu {
    param([string]$DatabasePath = "/data/CustomDRS.db")
    if (Test-Path /data/creds.xml) {
    	$Creds = Import-Clixml /data/creds.xml
    }
    if (Test-Path /data/vCenter.host) {
    	$device = Import-Clixml /data/vCenter.xml
	$vCenterHost = $device.Name
	$Cluster = $device.Cluster
    }
    while ($true) {
        Write-Host "`n=== CustomDRS Rule Management ===" -ForegroundColor Cyan
        Write-Host "1. View all rules"
        Write-Host "2. Add new rule"
        Write-Host "3. Update rule"
        Write-Host "4. Delete rule"
        Write-Host "5. View rule history"
        Write-Host "6. Export rules"
        Write-Host "7. Import rules"
        Write-Host "C. Connect vCenter"
        Write-Host "D. Disconnect vCenter"
        Write-Host "S. Save Credentials"
        Write-Host "V. Save vCenter Info"
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
            "C" {
                Connect-VIServer -Server $vCenterHost -Credential $Creds -Force
            }
            "D" {
                Disconnect-VIServer -Force
            }
            "S" {
                $TempCreds = Get-Credential
                $TempCreds | Export-Clixml /data/creds.xml
		$Creds = Import-Clixml /data/creds.xml
            }
            "V" {
                $TempHost = Read-Host "FQDN or IP of vCenter Server"
		$TempCluster = Read-Host "Cluster Name"
		$device = [pscustomobject]@{
    		    Name = $TempHost
		    Cluster = $TempCluster
		}
		$device | Export-Clixml -Path /data/vCenter.xml
		$vCenterHost = $device.Name
		$Cluster = $device.Cluster
	    }
            "8" {
                return
            }
        }
    }
}

function Initialize-SQLLite3 {
    <#
    .SYNOPSIS
    Initializes the CustomDRS SQLite database

    .DESCRIPTION
    Creates the SQLite database file and necessary tables for storing
    affinity rules, rule history, and audit logs

    .PARAMETER DatabasePath
    Path to the SQLite database file (default: CustomDRS.db in module directory)

    .EXAMPLE
    Initialize-CustomDRSDatabase -DatabasePath "C:\CustomDRS\rules.db"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$DatabasePath = (Join-Path $PSScriptRoot "CustomDRS.db")
    )

    Write-Verbose "Initializing CustomDRS database at: $DatabasePath"

    # Check if System.Data.SQLite is available
    $sqliteAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq "System.Data.SQLite" }

    if (-not $sqliteAssembly) {
        Write-Host "System.Data.SQLite not found. Attempting to load..." -ForegroundColor Yellow

        # Try to load from common paths
        $possiblePaths = @(
            "C:\Program Files\System.Data.SQLite\*\System.Data.SQLite.dll",
            "$env:ProgramFiles\System.Data.SQLite\*\System.Data.SQLite.dll",
            "${env:ProgramFiles(x86)}\System.Data.SQLite\*\System.Data.SQLite.dll",
            "$PSScriptRoot\System.Data.SQLite.dll"
        )

        $foundPath = $null
        foreach ($path in $possiblePaths) {
            $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
            if ($resolved) {
                $foundPath = $resolved | Select-Object -First 1 -ExpandProperty Path
                break
            }
        }

        if ($foundPath) {
            try {
                Add-Type -Path $foundPath
                Write-Host "Successfully loaded System.Data.SQLite" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to load System.Data.SQLite: $($_.Exception.Message)"
                Write-Host "`nTo install System.Data.SQLite:" -ForegroundColor Yellow
                Write-Host "1. Download from: https://system.data.sqlite.org/downloads/" -ForegroundColor Yellow
                Write-Host "2. Or install via NuGet: Install-Package System.Data.SQLite.Core" -ForegroundColor Yellow
                return $false
            }
        }
        else {
            Write-Error "System.Data.SQLite not found. Please install it first."
            Write-Host "`nTo install System.Data.SQLite:" -ForegroundColor Yellow
            Write-Host "1. Download from: https://system.data.sqlite.org/downloads/" -ForegroundColor Yellow
            Write-Host "2. Or use the included helper: Install-SQLiteDependency" -ForegroundColor Yellow
            return $false
        }
    }
}
#endregion

# Export module members
Export-ModuleMember -Function @(
    'Initialize-CustomDRSDatabase',
    'Add-CustomDRSAffinityRuleDB',
    'Get-CustomDRSAffinityRuleDB',
    'Update-CustomDRSAffinityRuleDB',
    'Remove-CustomDRSAffinityRuleDB',
    'Get-CustomDRSRuleHistory',
    'Add-CustomDRSRuleViolation',
    'Get-CustomDRSRuleViolations',
    'Export-CustomDRSRules',
    'Import-CustomDRSRules',
    'Invoke-CustomDRSLoadBalance',
    'Invoke-CustomDRSVMPlacement',
    'New-CustomDRSAffinityRule',
    'Get-CustomDRSRecommendations',
    'Enable-CustomDRSAutoBalance',
    'Get-CustomDRSClusterHealth',
    'Invoke-CustomDPM',
    'Show-RuleManagementMenu',
    'Initialize-SQLLite3',
    'Enable-CustomDRSAutoBalanceDB'
)
