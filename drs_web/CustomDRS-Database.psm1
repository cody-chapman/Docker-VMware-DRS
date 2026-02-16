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
    'Import-CustomDRSRules'
)
