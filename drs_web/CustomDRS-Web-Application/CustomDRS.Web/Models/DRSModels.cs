using System.ComponentModel.DataAnnotations;

namespace CustomDRS.Web.Models;

public class DRSRule
{
    public int RuleId { get; set; }
    
    [Required]
    [StringLength(100)]
    public string RuleName { get; set; } = string.Empty;
    
    [Required]
    public string RuleType { get; set; } = string.Empty; // Affinity or AntiAffinity
    
    public bool Enabled { get; set; } = true;
    
    [StringLength(100)]
    public string? ClusterName { get; set; }
    
    [StringLength(500)]
    public string? Description { get; set; }
    
    public DateTime CreatedDate { get; set; }
    public DateTime ModifiedDate { get; set; }
    
    public string? CreatedBy { get; set; }
    public string? ModifiedBy { get; set; }
    
    public List<string> VMs { get; set; } = new List<string>();
    public int VMCount => VMs.Count;
}

public class DRSRuleHistory
{
    public int HistoryId { get; set; }
    public int? RuleId { get; set; }
    public string RuleName { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public DateTime ActionDate { get; set; }
    public string? ActionBy { get; set; }
    public string? Details { get; set; }
}

public class DRSRuleViolation
{
    public int ViolationId { get; set; }
    public int RuleId { get; set; }
    public string RuleName { get; set; } = string.Empty;
    public string VMName { get; set; } = string.Empty;
    public string HostName { get; set; } = string.Empty;
    public string ViolationType { get; set; } = string.Empty;
    public DateTime DetectedDate { get; set; }
    public bool Resolved { get; set; }
    public DateTime? ResolvedDate { get; set; }
}

public class CreateRuleViewModel
{
    [Required]
    [StringLength(100)]
    [Display(Name = "Rule Name")]
    public string RuleName { get; set; } = string.Empty;
    
    [Required]
    [Display(Name = "Rule Type")]
    public string RuleType { get; set; } = "AntiAffinity";
    
    [Required]
    [Display(Name = "Virtual Machines")]
    public string VMNames { get; set; } = string.Empty; // Comma-separated
    
    [StringLength(100)]
    [Display(Name = "Cluster Name")]
    public string? ClusterName { get; set; }
    
    [StringLength(500)]
    [Display(Name = "Description")]
    public string? Description { get; set; }
    
    [Display(Name = "Enabled")]
    public bool Enabled { get; set; } = true;
}

public class EditRuleViewModel
{
    public int RuleId { get; set; }
    
    [Required]
    [StringLength(100)]
    [Display(Name = "Rule Name")]
    public string RuleName { get; set; } = string.Empty;
    
    [Required]
    [Display(Name = "Virtual Machines")]
    public string VMNames { get; set; } = string.Empty;
    
    [StringLength(100)]
    [Display(Name = "Cluster Name")]
    public string? ClusterName { get; set; }
    
    [StringLength(500)]
    [Display(Name = "Description")]
    public string? Description { get; set; }
    
    [Display(Name = "Enabled")]
    public bool Enabled { get; set; }
    
    public string RuleType { get; set; } = string.Empty;
}

public class DashboardViewModel
{
    public int TotalRules { get; set; }
    public int EnabledRules { get; set; }
    public int AffinityRules { get; set; }
    public int AntiAffinityRules { get; set; }
    public int UnresolvedViolations { get; set; }
    public List<DRSRule> RecentRules { get; set; } = new();
    public List<DRSRuleHistory> RecentHistory { get; set; } = new();
    public List<DRSRuleViolation> RecentViolations { get; set; } = new();
}
