using System.Data;
using System.Data.SQLite;
using CustomDRS.Web.Models;

namespace CustomDRS.Web.Services;

public interface IDRSRuleService
{
    Task<List<DRSRule>> GetAllRulesAsync();
    Task<List<DRSRule>> GetRulesByClusterAsync(string clusterName);
    Task<List<DRSRule>> GetEnabledRulesAsync();
    Task<DRSRule?> GetRuleByIdAsync(int ruleId);
    Task<DRSRule?> GetRuleByNameAsync(string ruleName);
    Task<int> CreateRuleAsync(DRSRule rule, string username);
    Task<bool> UpdateRuleAsync(DRSRule rule, string username);
    Task<bool> DeleteRuleAsync(int ruleId, string username);
    Task<List<DRSRuleHistory>> GetRuleHistoryAsync(int? ruleId = null, int days = 30);
    Task<List<DRSRuleViolation>> GetViolationsAsync(bool unresolvedOnly = false, int days = 30);
    Task<bool> InitializeDatabaseAsync();
}

public class DRSRuleService : IDRSRuleService
{
    private readonly string _connectionString;
    private readonly ILogger<DRSRuleService> _logger;

    public DRSRuleService(IConfiguration configuration, ILogger<DRSRuleService> logger)
    {
        _connectionString = configuration.GetConnectionString("DRSRulesConnection") 
            ?? "Data Source=/var/lib/customdrs/rules.db";
        _logger = logger;
        
        // Ensure directory exists
        var dbPath = _connectionString.Replace("Data Source=", "");
        var dbDirectory = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dbDirectory) && !Directory.Exists(dbDirectory))
        {
            Directory.CreateDirectory(dbDirectory);
        }
    }

    private SQLiteConnection GetConnection()
    {
        return new SQLiteConnection(_connectionString);
    }

    public async Task<bool> InitializeDatabaseAsync()
    {
        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var createTables = @"
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

                CREATE TABLE IF NOT EXISTS RuleVMs (
                    RuleVMId INTEGER PRIMARY KEY AUTOINCREMENT,
                    RuleId INTEGER NOT NULL,
                    VMName TEXT NOT NULL,
                    AddedDate TEXT NOT NULL,
                    FOREIGN KEY (RuleId) REFERENCES AffinityRules(RuleId) ON DELETE CASCADE,
                    UNIQUE(RuleId, VMName)
                );

                CREATE TABLE IF NOT EXISTS RuleHistory (
                    HistoryId INTEGER PRIMARY KEY AUTOINCREMENT,
                    RuleId INTEGER,
                    RuleName TEXT NOT NULL,
                    Action TEXT NOT NULL,
                    ActionDate TEXT NOT NULL,
                    ActionBy TEXT,
                    Details TEXT
                );

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

                CREATE INDEX IF NOT EXISTS idx_rulevms_ruleid ON RuleVMs(RuleId);
                CREATE INDEX IF NOT EXISTS idx_rulevms_vmname ON RuleVMs(VMName);
                CREATE INDEX IF NOT EXISTS idx_history_ruleid ON RuleHistory(RuleId);
                CREATE INDEX IF NOT EXISTS idx_violations_ruleid ON RuleViolations(RuleId);
                CREATE INDEX IF NOT EXISTS idx_violations_resolved ON RuleViolations(Resolved);
            ";

            using var command = new SQLiteCommand(createTables, connection);
            await command.ExecuteNonQueryAsync();

            _logger.LogInformation("DRS Rules database initialized successfully");
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize DRS Rules database");
            return false;
        }
    }

    public async Task<List<DRSRule>> GetAllRulesAsync()
    {
        var rules = new List<DRSRule>();

        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT 
                    r.RuleId, r.RuleName, r.RuleType, r.Enabled, r.ClusterName, r.Description,
                    r.CreatedDate, r.ModifiedDate, r.CreatedBy, r.ModifiedBy,
                    GROUP_CONCAT(rv.VMName, ',') as VMs
                FROM AffinityRules r
                LEFT JOIN RuleVMs rv ON r.RuleId = rv.RuleId
                GROUP BY r.RuleId
                ORDER BY r.RuleName;
            ";

            using var command = new SQLiteCommand(query, connection);
            using var reader = await command.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                rules.Add(MapRule(reader));
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve all rules");
        }

        return rules;
    }

    public async Task<List<DRSRule>> GetRulesByClusterAsync(string clusterName)
    {
        var rules = new List<DRSRule>();

        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT 
                    r.RuleId, r.RuleName, r.RuleType, r.Enabled, r.ClusterName, r.Description,
                    r.CreatedDate, r.ModifiedDate, r.CreatedBy, r.ModifiedBy,
                    GROUP_CONCAT(rv.VMName, ',') as VMs
                FROM AffinityRules r
                LEFT JOIN RuleVMs rv ON r.RuleId = rv.RuleId
                WHERE r.ClusterName = @ClusterName
                GROUP BY r.RuleId
                ORDER BY r.RuleName;
            ";

            using var command = new SQLiteCommand(query, connection);
            command.Parameters.AddWithValue("@ClusterName", clusterName);
            using var reader = await command.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                rules.Add(MapRule(reader));
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve rules for cluster {Cluster}", clusterName);
        }

        return rules;
    }

    public async Task<List<DRSRule>> GetEnabledRulesAsync()
    {
        var rules = new List<DRSRule>();

        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT 
                    r.RuleId, r.RuleName, r.RuleType, r.Enabled, r.ClusterName, r.Description,
                    r.CreatedDate, r.ModifiedDate, r.CreatedBy, r.ModifiedBy,
                    GROUP_CONCAT(rv.VMName, ',') as VMs
                FROM AffinityRules r
                LEFT JOIN RuleVMs rv ON r.RuleId = rv.RuleId
                WHERE r.Enabled = 1
                GROUP BY r.RuleId
                ORDER BY r.RuleName;
            ";

            using var command = new SQLiteCommand(query, connection);
            using var reader = await command.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                rules.Add(MapRule(reader));
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve enabled rules");
        }

        return rules;
    }

    public async Task<DRSRule?> GetRuleByIdAsync(int ruleId)
    {
        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT 
                    r.RuleId, r.RuleName, r.RuleType, r.Enabled, r.ClusterName, r.Description,
                    r.CreatedDate, r.ModifiedDate, r.CreatedBy, r.ModifiedBy,
                    GROUP_CONCAT(rv.VMName, ',') as VMs
                FROM AffinityRules r
                LEFT JOIN RuleVMs rv ON r.RuleId = rv.RuleId
                WHERE r.RuleId = @RuleId
                GROUP BY r.RuleId;
            ";

            using var command = new SQLiteCommand(query, connection);
            command.Parameters.AddWithValue("@RuleId", ruleId);
            using var reader = await command.ExecuteReaderAsync();

            if (await reader.ReadAsync())
            {
                return MapRule(reader);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve rule {RuleId}", ruleId);
        }

        return null;
    }

    public async Task<DRSRule?> GetRuleByNameAsync(string ruleName)
    {
        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT 
                    r.RuleId, r.RuleName, r.RuleType, r.Enabled, r.ClusterName, r.Description,
                    r.CreatedDate, r.ModifiedDate, r.CreatedBy, r.ModifiedBy,
                    GROUP_CONCAT(rv.VMName, ',') as VMs
                FROM AffinityRules r
                LEFT JOIN RuleVMs rv ON r.RuleId = rv.RuleId
                WHERE r.RuleName = @RuleName
                GROUP BY r.RuleId;
            ";

            using var command = new SQLiteCommand(query, connection);
            command.Parameters.AddWithValue("@RuleName", ruleName);
            using var reader = await command.ExecuteReaderAsync();

            if (await reader.ReadAsync())
            {
                return MapRule(reader);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve rule {RuleName}", ruleName);
        }

        return null;
    }

    public async Task<int> CreateRuleAsync(DRSRule rule, string username)
    {
        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            using var transaction = connection.BeginTransaction();

            try
            {
                // Insert rule
                var insertRule = @"
                    INSERT INTO AffinityRules (RuleName, RuleType, Enabled, ClusterName, Description, CreatedDate, ModifiedDate, CreatedBy, ModifiedBy)
                    VALUES (@RuleName, @RuleType, @Enabled, @ClusterName, @Description, @CreatedDate, @ModifiedDate, @CreatedBy, @ModifiedBy);
                    SELECT last_insert_rowid();
                ";

                using var command = new SQLiteCommand(insertRule, connection, transaction);
                command.Parameters.AddWithValue("@RuleName", rule.RuleName);
                command.Parameters.AddWithValue("@RuleType", rule.RuleType);
                command.Parameters.AddWithValue("@Enabled", rule.Enabled ? 1 : 0);
                command.Parameters.AddWithValue("@ClusterName", (object?)rule.ClusterName ?? DBNull.Value);
                command.Parameters.AddWithValue("@Description", (object?)rule.Description ?? DBNull.Value);
                command.Parameters.AddWithValue("@CreatedDate", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                command.Parameters.AddWithValue("@ModifiedDate", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                command.Parameters.AddWithValue("@CreatedBy", username);
                command.Parameters.AddWithValue("@ModifiedBy", username);

                var ruleId = Convert.ToInt32(await command.ExecuteScalarAsync());

                // Insert VMs
                foreach (var vm in rule.VMs)
                {
                    var insertVM = "INSERT INTO RuleVMs (RuleId, VMName, AddedDate) VALUES (@RuleId, @VMName, @AddedDate);";
                    using var vmCommand = new SQLiteCommand(insertVM, connection, transaction);
                    vmCommand.Parameters.AddWithValue("@RuleId", ruleId);
                    vmCommand.Parameters.AddWithValue("@VMName", vm);
                    vmCommand.Parameters.AddWithValue("@AddedDate", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                    await vmCommand.ExecuteNonQueryAsync();
                }

                // Add history
                await AddHistoryAsync(connection, transaction, ruleId, rule.RuleName, "Created", username, $"Rule created with {rule.VMs.Count} VMs");

                transaction.Commit();
                _logger.LogInformation("Created rule {RuleName} with ID {RuleId}", rule.RuleName, ruleId);
                return ruleId;
            }
            catch
            {
                transaction.Rollback();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create rule {RuleName}", rule.RuleName);
            return 0;
        }
    }

    public async Task<bool> UpdateRuleAsync(DRSRule rule, string username)
    {
        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            using var transaction = connection.BeginTransaction();

            try
            {
                // Update rule
                var updateRule = @"
                    UPDATE AffinityRules 
                    SET RuleName = @RuleName, 
                        Enabled = @Enabled, 
                        ClusterName = @ClusterName, 
                        Description = @Description,
                        ModifiedDate = @ModifiedDate,
                        ModifiedBy = @ModifiedBy
                    WHERE RuleId = @RuleId;
                ";

                using var command = new SQLiteCommand(updateRule, connection, transaction);
                command.Parameters.AddWithValue("@RuleId", rule.RuleId);
                command.Parameters.AddWithValue("@RuleName", rule.RuleName);
                command.Parameters.AddWithValue("@Enabled", rule.Enabled ? 1 : 0);
                command.Parameters.AddWithValue("@ClusterName", (object?)rule.ClusterName ?? DBNull.Value);
                command.Parameters.AddWithValue("@Description", (object?)rule.Description ?? DBNull.Value);
                command.Parameters.AddWithValue("@ModifiedDate", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                command.Parameters.AddWithValue("@ModifiedBy", username);

                await command.ExecuteNonQueryAsync();

                // Delete existing VMs
                var deleteVMs = "DELETE FROM RuleVMs WHERE RuleId = @RuleId;";
                using var deleteCommand = new SQLiteCommand(deleteVMs, connection, transaction);
                deleteCommand.Parameters.AddWithValue("@RuleId", rule.RuleId);
                await deleteCommand.ExecuteNonQueryAsync();

                // Insert new VMs
                foreach (var vm in rule.VMs)
                {
                    var insertVM = "INSERT INTO RuleVMs (RuleId, VMName, AddedDate) VALUES (@RuleId, @VMName, @AddedDate);";
                    using var vmCommand = new SQLiteCommand(insertVM, connection, transaction);
                    vmCommand.Parameters.AddWithValue("@RuleId", rule.RuleId);
                    vmCommand.Parameters.AddWithValue("@VMName", vm);
                    vmCommand.Parameters.AddWithValue("@AddedDate", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                    await vmCommand.ExecuteNonQueryAsync();
                }

                // Add history
                await AddHistoryAsync(connection, transaction, rule.RuleId, rule.RuleName, "Updated", username, $"Rule updated with {rule.VMs.Count} VMs");

                transaction.Commit();
                _logger.LogInformation("Updated rule {RuleName}", rule.RuleName);
                return true;
            }
            catch
            {
                transaction.Rollback();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to update rule {RuleName}", rule.RuleName);
            return false;
        }
    }

    public async Task<bool> DeleteRuleAsync(int ruleId, string username)
    {
        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            using var transaction = connection.BeginTransaction();

            try
            {
                // Get rule name for history
                var getNameQuery = "SELECT RuleName FROM AffinityRules WHERE RuleId = @RuleId;";
                using var nameCommand = new SQLiteCommand(getNameQuery, connection, transaction);
                nameCommand.Parameters.AddWithValue("@RuleId", ruleId);
                var ruleName = (await nameCommand.ExecuteScalarAsync())?.ToString() ?? "Unknown";

                // Add history before deletion
                await AddHistoryAsync(connection, transaction, ruleId, ruleName, "Deleted", username, "Rule deleted");

                // Delete rule (cascade will delete VMs)
                var deleteRule = "DELETE FROM AffinityRules WHERE RuleId = @RuleId;";
                using var command = new SQLiteCommand(deleteRule, connection, transaction);
                command.Parameters.AddWithValue("@RuleId", ruleId);
                await command.ExecuteNonQueryAsync();

                transaction.Commit();
                _logger.LogInformation("Deleted rule {RuleName} (ID: {RuleId})", ruleName, ruleId);
                return true;
            }
            catch
            {
                transaction.Rollback();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete rule {RuleId}", ruleId);
            return false;
        }
    }

    public async Task<List<DRSRuleHistory>> GetRuleHistoryAsync(int? ruleId = null, int days = 30)
    {
        var history = new List<DRSRuleHistory>();

        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT HistoryId, RuleId, RuleName, Action, ActionDate, ActionBy, Details
                FROM RuleHistory
                WHERE ActionDate >= datetime('now', '-' || @Days || ' days')
            ";

            if (ruleId.HasValue)
            {
                query += " AND RuleId = @RuleId";
            }

            query += " ORDER BY ActionDate DESC;";

            using var command = new SQLiteCommand(query, connection);
            command.Parameters.AddWithValue("@Days", days);
            if (ruleId.HasValue)
            {
                command.Parameters.AddWithValue("@RuleId", ruleId.Value);
            }

            using var reader = await command.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                history.Add(new DRSRuleHistory
                {
                    HistoryId = reader.GetInt32(0),
                    RuleId = reader.IsDBNull(1) ? null : reader.GetInt32(1),
                    RuleName = reader.GetString(2),
                    Action = reader.GetString(3),
                    ActionDate = DateTime.Parse(reader.GetString(4)),
                    ActionBy = reader.IsDBNull(5) ? null : reader.GetString(5),
                    Details = reader.IsDBNull(6) ? null : reader.GetString(6)
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve rule history");
        }

        return history;
    }

    public async Task<List<DRSRuleViolation>> GetViolationsAsync(bool unresolvedOnly = false, int days = 30)
    {
        var violations = new List<DRSRuleViolation>();

        try
        {
            using var connection = GetConnection();
            await connection.OpenAsync();

            var query = @"
                SELECT ViolationId, RuleId, RuleName, VMName, HostName, ViolationType, DetectedDate, Resolved, ResolvedDate
                FROM RuleViolations
                WHERE DetectedDate >= datetime('now', '-' || @Days || ' days')
            ";

            if (unresolvedOnly)
            {
                query += " AND Resolved = 0";
            }

            query += " ORDER BY DetectedDate DESC;";

            using var command = new SQLiteCommand(query, connection);
            command.Parameters.AddWithValue("@Days", days);

            using var reader = await command.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                violations.Add(new DRSRuleViolation
                {
                    ViolationId = reader.GetInt32(0),
                    RuleId = reader.GetInt32(1),
                    RuleName = reader.GetString(2),
                    VMName = reader.GetString(3),
                    HostName = reader.GetString(4),
                    ViolationType = reader.GetString(5),
                    DetectedDate = DateTime.Parse(reader.GetString(6)),
                    Resolved = reader.GetInt32(7) == 1,
                    ResolvedDate = reader.IsDBNull(8) ? null : DateTime.Parse(reader.GetString(8))
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve violations");
        }

        return violations;
    }

    private DRSRule MapRule(SQLiteDataReader reader)
    {
        var vmList = new List<string>();
        if (!reader.IsDBNull(reader.GetOrdinal("VMs")))
        {
            var vmsString = reader.GetString(reader.GetOrdinal("VMs"));
            if (!string.IsNullOrEmpty(vmsString))
            {
                vmList = vmsString.Split(',').ToList();
            }
        }

        return new DRSRule
        {
            RuleId = reader.GetInt32(reader.GetOrdinal("RuleId")),
            RuleName = reader.GetString(reader.GetOrdinal("RuleName")),
            RuleType = reader.GetString(reader.GetOrdinal("RuleType")),
            Enabled = reader.GetInt32(reader.GetOrdinal("Enabled")) == 1,
            ClusterName = reader.IsDBNull(reader.GetOrdinal("ClusterName")) ? null : reader.GetString(reader.GetOrdinal("ClusterName")),
            Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
            CreatedDate = DateTime.Parse(reader.GetString(reader.GetOrdinal("CreatedDate"))),
            ModifiedDate = DateTime.Parse(reader.GetString(reader.GetOrdinal("ModifiedDate"))),
            CreatedBy = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetString(reader.GetOrdinal("CreatedBy")),
            ModifiedBy = reader.IsDBNull(reader.GetOrdinal("ModifiedBy")) ? null : reader.GetString(reader.GetOrdinal("ModifiedBy")),
            VMs = vmList
        };
    }

    private async Task AddHistoryAsync(SQLiteConnection connection, SQLiteTransaction transaction, int ruleId, string ruleName, string action, string username, string details)
    {
        var insertHistory = @"
            INSERT INTO RuleHistory (RuleId, RuleName, Action, ActionDate, ActionBy, Details)
            VALUES (@RuleId, @RuleName, @Action, @ActionDate, @ActionBy, @Details);
        ";

        using var command = new SQLiteCommand(insertHistory, connection, transaction);
        command.Parameters.AddWithValue("@RuleId", ruleId);
        command.Parameters.AddWithValue("@RuleName", ruleName);
        command.Parameters.AddWithValue("@Action", action);
        command.Parameters.AddWithValue("@ActionDate", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
        command.Parameters.AddWithValue("@ActionBy", username);
        command.Parameters.AddWithValue("@Details", details);

        await command.ExecuteNonQueryAsync();
    }
}
