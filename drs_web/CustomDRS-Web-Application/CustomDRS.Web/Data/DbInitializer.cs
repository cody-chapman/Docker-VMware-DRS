using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using CustomDRS.Web.Models;

namespace CustomDRS.Web.Data;

public static class DbInitializer
{
    public static async Task Initialize(
        ApplicationDbContext context,
        UserManager<ApplicationUser> userManager,
        RoleManager<IdentityRole> roleManager)
    {
        // Ensure database is created
        await context.Database.MigrateAsync();
        
        // Create roles
        string[] roles = { "Admin", "User" };
        
        foreach (var role in roles)
        {
            if (!await roleManager.RoleExistsAsync(role))
            {
                await roleManager.CreateAsync(new IdentityRole(role));
            }
        }
        
        // Create default admin user
        var adminEmail = "admin@customdrs.local";
        var adminUser = await userManager.FindByEmailAsync(adminEmail);
        
        if (adminUser == null)
        {
            adminUser = new ApplicationUser
            {
                UserName = "admin",
                Email = adminEmail,
                EmailConfirmed = true,
                FullName = "Administrator",
                CreatedDate = DateTime.UtcNow
            };
            
            var result = await userManager.CreateAsync(adminUser, "ChangeMe123!");
            
            if (result.Succeeded)
            {
                await userManager.AddToRoleAsync(adminUser, "Admin");
                Console.WriteLine("Default admin user created successfully!");
                Console.WriteLine($"Username: admin");
                Console.WriteLine($"Email: {adminEmail}");
                Console.WriteLine($"Password: ChangeMe123!");
                Console.WriteLine("IMPORTANT: Change the default password immediately!");
            }
            else
            {
                Console.WriteLine("Failed to create default admin user:");
                foreach (var error in result.Errors)
                {
                    Console.WriteLine($"- {error.Description}");
                }
            }
        }
    }
}
