# CustomDRS Web Application

ASP.NET Core 8.0 web application for managing VMware DRS affinity rules with SQLite backend.

## Features

- ✅ **User Authentication** - Login/logout with Identity framework
- ✅ **Role-Based Access** - Admin and User roles
- ✅ **DRS Rule Management** - Create, edit, delete affinity/anti-affinity rules
- ✅ **Rule History** - Complete audit trail of all changes
- ✅ **Violation Tracking** - Monitor and track rule violations
- ✅ **Dashboard** - Overview of rules and recent activity
- ✅ **SQLite Database** - Self-contained, no external database required
- ✅ **Debian 12 Ready** - Optimized for Linux deployment

## Prerequisites

### For Development
- .NET 8 SDK
- Any text editor or IDE (VS Code, Visual Studio, Rider)

### For Deployment on Debian 12
- .NET 8 Runtime (or SDK)
- systemd (included in Debian 12)
- sudo access for system service setup

## Installation on Debian 12

### 1. Install .NET 8

```bash
# Add Microsoft package repository
wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Install .NET SDK (includes runtime)
sudo apt-get update
sudo apt-get install -y dotnet-sdk-8.0

# Verify installation
dotnet --version
```

### 2. Deploy the Application

```bash
# Navigate to the application directory
cd CustomDRS.Web

# Run the deployment script
chmod +x build-and-deploy.sh
./build-and-deploy.sh
```

The script will:
- Create necessary directories (`/var/lib/customdrs`, `/var/log/customdrs`, `/opt/customdrs`)
- Build and publish the application
- Create a systemd service
- Configure the application for production

### 3. Start the Service

```bash
# Start the application
sudo systemctl start customdrs-web

# Check status
sudo systemctl status customdrs-web

# View logs
sudo journalctl -u customdrs-web -f
```

### 4. Access the Application

Open your browser and navigate to:
- **Local**: http://localhost:5000
- **Remote**: http://YOUR_SERVER_IP:5000

**Default Login:**
- Username: `admin`
- Email: `admin@customdrs.local`
- Password: `ChangeMe123!`

⚠️ **IMPORTANT**: Change the default password immediately after first login!

## Manual Build and Run

### Development Mode

```bash
# Restore packages
dotnet restore

# Run in development mode
dotnet run

# Application will be available at http://localhost:5000
```

### Production Build

```bash
# Build
dotnet build -c Release

# Publish
dotnet publish -c Release -o ./publish

# Run
cd publish
dotnet CustomDRS.Web.dll
```

## Configuration

### Database Locations

- **Identity Database**: `/var/lib/customdrs/identity.db`
- **DRS Rules Database**: `/var/lib/customdrs/rules.db`

### Configuration File

Edit `/opt/customdrs/publish/appsettings.Production.json` to change:
- Database paths
- Logging settings
- Other application settings

### Changing Port

To change the default port (5000), modify `Program.cs`:

```csharp
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(YOUR_PORT); // Change 5000 to your preferred port
});
```

Then rebuild and redeploy.

## Usage

### Dashboard
- View overview of all rules
- See recent activity and violations
- Quick statistics

### Managing Rules

**Create Rule:**
1. Navigate to Rules → Create New
2. Fill in rule details:
   - Name (unique identifier)
   - Type (Affinity or Anti-Affinity)
   - Virtual Machines (comma-separated list)
   - Cluster Name (optional)
   - Description (optional)
3. Click Create

**Edit Rule:**
1. Navigate to Rules → All Rules
2. Click Edit on any rule
3. Modify details
4. Click Update

**Delete Rule:**
1. Navigate to Rules → All Rules
2. Click Delete on any rule
3. Confirm deletion

### User Management (Admin Only)

**Create User:**
1. Navigate to Account → Users
2. Click Register New User
3. Fill in user details
4. User will be created with "User" role

**Delete User:**
1. Navigate to Account → Users
2. Click Delete next to any user
3. Confirm deletion

## Security

### Password Requirements
- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one digit
- At least one special character

### Account Lockout
- Maximum 5 failed login attempts
- 15-minute lockout period

### Sessions
- 2-hour session timeout
- Sliding expiration (extends with activity)

### Database Security
- SQLite databases stored in `/var/lib/customdrs/`
- Accessible only by the application user
- Regular backups recommended

## Backup and Restore

### Backup

```bash
# Stop the service
sudo systemctl stop customdrs-web

# Backup databases
sudo cp /var/lib/customdrs/identity.db /backup/identity-$(date +%Y%m%d).db
sudo cp /var/lib/customdrs/rules.db /backup/rules-$(date +%Y%m%d).db

# Start the service
sudo systemctl start customdrs-web
```

### Restore

```bash
# Stop the service
sudo systemctl stop customdrs-web

# Restore databases
sudo cp /backup/identity-YYYYMMDD.db /var/lib/customdrs/identity.db
sudo cp /backup/rules-YYYYMMDD.db /var/lib/customdrs/rules.db

# Fix permissions
sudo chown $USER:$USER /var/lib/customdrs/*.db

# Start the service
sudo systemctl start customdrs-web
```

## Maintenance

### View Logs

```bash
# Application logs
sudo journalctl -u customdrs-web -f

# Or log file (if configured)
sudo tail -f /var/log/customdrs/app.log
```

### Restart Service

```bash
sudo systemctl restart customdrs-web
```

### Update Application

```bash
# Stop service
sudo systemctl stop customdrs-web

# Pull latest code or copy new version
cd CustomDRS.Web

# Rebuild and republish
./build-and-deploy.sh

# Start service
sudo systemctl start customdrs-web
```

### Database Maintenance

```bash
# Check database integrity
sqlite3 /var/lib/customdrs/rules.db "PRAGMA integrity_check;"

# Vacuum database (optimize)
sqlite3 /var/lib/customdrs/rules.db "VACUUM;"

# View database size
du -h /var/lib/customdrs/*.db
```

## Troubleshooting

### Service Won't Start

```bash
# Check status and logs
sudo systemctl status customdrs-web
sudo journalctl -u customdrs-web -n 50

# Common issues:
# 1. Port already in use - check with: sudo netstat -tlnp | grep 5000
# 2. Permission issues - check file ownership
# 3. Missing .NET runtime - verify with: dotnet --version
```

### Database Errors

```bash
# Check database exists
ls -l /var/lib/customdrs/

# Check permissions
sudo chown -R $USER:$USER /var/lib/customdrs/

# Initialize database manually
cd /opt/customdrs/publish
dotnet CustomDRS.Web.dll
```

### Can't Login

```bash
# Reset admin password (requires database access)
# Stop service
sudo systemctl stop customdrs-web

# Delete identity database (will recreate with default admin)
sudo rm /var/lib/customdrs/identity.db

# Start service (will create new admin with default password)
sudo systemctl start customdrs-web
```

### High CPU/Memory Usage

```bash
# Check resource usage
sudo systemctl status customdrs-web

# Monitor in real-time
top -p $(pgrep -f CustomDRS.Web)

# Restart if needed
sudo systemctl restart customdrs-web
```

## Firewall Configuration

If using UFW:

```bash
# Allow HTTP traffic
sudo ufw allow 5000/tcp

# Check status
sudo ufw status
```

For iptables:

```bash
sudo iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
sudo iptables-save
```

## HTTPS/SSL Setup

For production, it's recommended to use a reverse proxy (nginx/Apache) with SSL:

### Using nginx

```bash
# Install nginx
sudo apt-get install nginx

# Create nginx config
sudo nano /etc/nginx/sites-available/customdrs

# Add configuration:
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Enable site
sudo ln -s /etc/nginx/sites-available/customdrs /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Install Certbot for Let's Encrypt SSL
sudo apt-get install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

## API Integration

The web application can be integrated with PowerShell scripts for automation:

```powershell
# Example: Get rules from web application
$baseUri = "http://your-server:5000"
$rules = Invoke-RestMethod -Uri "$baseUri/api/rules" -Method Get

# Use rules with CustomDRS PowerShell module
$affinityRules = $rules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.RuleName
        Type = $_.RuleType
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

Invoke-CustomDRSLoadBalance -Cluster $cluster -AffinityRules $affinityRules -AutoApply
```

## Development

### Project Structure

```
CustomDRS.Web/
├── Controllers/         # MVC Controllers
├── Models/             # Data models and view models
├── Views/              # Razor views
├── Services/           # Business logic and data access
├── Data/               # Database contexts
├── wwwroot/            # Static files (CSS, JS, images)
├── Program.cs          # Application entry point
├── appsettings.json    # Configuration
└── CustomDRS.Web.csproj # Project file
```

### Adding New Features

1. Create model in `Models/`
2. Add service in `Services/`
3. Create controller in `Controllers/`
4. Add views in `Views/[ControllerName]/`
5. Update navigation in `Views/Shared/_Layout.cshtml`

## Performance Tuning

### Database Optimization

```bash
# Add indexes for common queries
sqlite3 /var/lib/customdrs/rules.db << EOF
CREATE INDEX IF NOT EXISTS idx_rules_cluster ON AffinityRules(ClusterName);
CREATE INDEX IF NOT EXISTS idx_rules_enabled ON AffinityRules(Enabled);
CREATE INDEX IF NOT EXISTS idx_history_date ON RuleHistory(ActionDate);
