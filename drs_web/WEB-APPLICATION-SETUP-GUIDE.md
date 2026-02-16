# CustomDRS Web Application - Complete Setup Guide

## Overview

The CustomDRS Web Application is an ASP.NET Core 8.0 web interface for managing VMware DRS affinity and anti-affinity rules. It provides user authentication, role-based access control, and a complete web UI for rule management.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              CustomDRS Web Application                   │
│                   (ASP.NET Core 8)                      │
├─────────────────────────────────────────────────────────┤
│  Authentication  │  Rule Management  │   Dashboard      │
│  (Identity)      │  (CRUD)           │   (Statistics)   │
└────────┬─────────┴──────────┬────────┴──────────────────┘
         │                     │
    ┌────▼──────┐         ┌───▼────────┐
    │ Identity  │         │ DRS Rules  │
    │ Database  │         │ Database   │
    │ (SQLite)  │         │ (SQLite)   │
    └───────────┘         └────────────┘
```

## Prerequisites

### System Requirements
- **Operating System**: Debian 12 (Bookworm) - 64-bit
- **RAM**: Minimum 512MB, Recommended 1GB+
- **Disk Space**: 500MB for application + databases
- **Network**: Port 5000 accessible (or custom port)

### Software Requirements
- **.NET 8 Runtime** or **.NET 8 SDK** (SDK includes runtime)
- **systemd** (included in Debian 12)
- **sudo access** for system service installation

## Installation Steps

### Step 1: Extract the Application

```bash
# Extract the archive
tar -xzf CustomDRS-Web-Application.tar.gz
cd CustomDRS.Web
```

### Step 2: Install .NET 8 SDK

```bash
# Download Microsoft package repository configuration
wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb

# Install the repository configuration
sudo dpkg -i packages-microsoft-prod.deb

# Clean up
rm packages-microsoft-prod.deb

# Update package lists
sudo apt-get update

# Install .NET 8 SDK
sudo apt-get install -y dotnet-sdk-8.0

# Verify installation
dotnet --version
# Should output: 8.0.x
```

### Step 3: Build and Deploy

```bash
# Make the deployment script executable
chmod +x build-and-deploy.sh

# Run the deployment script
./build-and-deploy.sh
```

The script will:
1. Verify .NET SDK is installed
2. Create directory structure:
   - `/var/lib/customdrs` - Database storage
   - `/var/log/customdrs` - Log files
   - `/opt/customdrs` - Application files
3. Build the application
4. Publish to `/opt/customdrs/publish`
5. Create systemd service
6. Enable the service

### Step 4: Start the Application

```bash
# Start the service
sudo systemctl start customdrs-web

# Check status
sudo systemctl status customdrs-web

# If running successfully, you should see:
# ● customdrs-web.service - CustomDRS Web Application
#    Loaded: loaded (/etc/systemd/system/customdrs-web.service)
#    Active: active (running)
```

### Step 5: Access the Application

Open your web browser and navigate to:

- **Local Access**: http://localhost:5000
- **Remote Access**: http://YOUR_SERVER_IP:5000

**Default Administrator Credentials:**
- Username: `admin`
- Email: `admin@customdrs.local`
- Password: `ChangeMe123!`

⚠️ **CRITICAL**: Change the default password immediately after first login!

## Configuration

### Database Configuration

Edit `/opt/customdrs/publish/appsettings.Production.json`:

```json
{
  "ConnectionStrings": {
    "IdentityConnection": "Data Source=/var/lib/customdrs/identity.db",
    "DRSRulesConnection": "Data Source=/var/lib/customdrs/rules.db"
  }
}
```

### Changing the Port

To use a different port:

1. Edit `/opt/customdrs/publish/Program.cs` or rebuild with modified port
2. Update the port number in `ConfigureKestrel`
3. Restart the service

Or edit the published DLL configuration before first run.

### Logging Configuration

Logs are written to:
- System Journal: `sudo journalctl -u customdrs-web -f`
- File (if configured): `/var/log/customdrs/app.log`

## Usage Guide

### First Login

1. Navigate to http://YOUR_SERVER:5000
2. Click "Login"
3. Enter default credentials
4. You'll be redirected to the dashboard
5. Immediately change password: Account → Change Password

### Creating Users (Admin Only)

1. Navigate to **Account** → **Users**
2. Click **Register New User**
3. Fill in:
   - Username
   - Email
   - Full Name
   - Password (must meet complexity requirements)
4. Click **Register**
5. New user is created with "User" role

### Managing DRS Rules

#### Create a Rule

1. Navigate to **Rules** → **Create New**
2. Fill in the form:
   - **Rule Name**: Unique identifier (e.g., "DomainControllers-AntiAffinity")
   - **Rule Type**: 
     - `Affinity` - Keep VMs together on same host
     - `AntiAffinity` - Keep VMs on separate hosts
   - **Virtual Machines**: Comma-separated list (e.g., "DC01, DC02, DC03")
   - **Cluster Name**: Optional (e.g., "Production")
   - **Description**: Optional details
   - **Enabled**: Check to enable immediately
3. Click **Create**

#### View All Rules

1. Navigate to **Rules** → **All Rules**
2. View list of all rules with:
   - Rule name and type
   - Number of VMs
   - Cluster assignment
   - Enabled status
   - Actions (Edit/Delete)

#### Edit a Rule

1. Go to **Rules** → **All Rules**
2. Click **Edit** on the rule
3. Modify fields (cannot change Rule Type)
4. Click **Update**

#### Delete a Rule

1. Go to **Rules** → **All Rules**
2. Click **Delete** on the rule
3. Confirm deletion
4. Rule and history are removed

### Viewing History

1. Navigate to **Rules** → **History**
2. View audit trail of all rule changes:
   - Action (Created/Updated/Deleted)
   - Rule name
   - Date and time
   - User who made the change
   - Details of the change

### Monitoring Violations

1. Navigate to **Rules** → **Violations**
2. View logged rule violations:
   - Rule name
   - VM name
   - Host name
   - Violation type
   - Detection date
   - Resolution status

## Integration with PowerShell

### Loading Rules from Web Application

The web application shares the same SQLite database as the PowerShell module, so rules created in the web UI are immediately available to PowerShell scripts:

```powershell
# Import modules
Import-Module .\CustomDRS.psm1
Import-Module .\CustomDRS-Database.psm1

# Connect to vCenter
Connect-VIServer -Server "vcenter.domain.com"

# Get cluster
$cluster = Get-Cluster "Production"

# Load rules from database (same database as web app)
$dbRules = Get-CustomDRSAffinityRuleDB -EnabledOnly -DatabasePath "/var/lib/customdrs/rules.db"

# Convert to CustomDRS format
$affinityRules = $dbRules | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.Type
        VMs = $_.VMs
        Enabled = $_.Enabled
    }
}

# Run load balancing with web-managed rules
Invoke-CustomDRSLoadBalance `
    -Cluster $cluster `
    -AggressivenessLevel 3 `
    -AffinityRules $affinityRules `
    -AutoApply
```

### Automated Workflow

1. **Web UI**: Administrators manage rules through web interface
2. **Database**: Rules stored in SQLite database
3. **PowerShell**: Scheduled scripts read rules from database and apply DRS balancing
4. **Feedback**: Violations detected by PowerShell can be logged to database

## Maintenance

### View Logs

```bash
# Real-time logs
sudo journalctl -u customdrs-web -f

# Last 100 lines
sudo journalctl -u customdrs-web -n 100

# Logs since yesterday
sudo journalctl -u customdrs-web --since yesterday
```

### Restart Service

```bash
sudo systemctl restart customdrs-web
```

### Stop Service

```bash
sudo systemctl stop customdrs-web
```

### Check Service Status

```bash
sudo systemctl status customdrs-web
```

### Update Application

```bash
# Stop service
sudo systemctl stop customdrs-web

# Backup databases
sudo cp /var/lib/customdrs/*.db /backup/

# Extract new version
tar -xzf CustomDRS-Web-Application-v2.tar.gz
cd CustomDRS.Web

# Rebuild and deploy
./build-and-deploy.sh

# Start service
sudo systemctl start customdrs-web
```

## Backup and Restore

### Backup

```bash
#!/bin/bash
# backup-customdrs.sh

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/backup/customdrs"

# Create backup directory
mkdir -p $BACKUP_DIR

# Stop service
sudo systemctl stop customdrs-web

# Backup databases
sudo cp /var/lib/customdrs/identity.db $BACKUP_DIR/identity-$DATE.db
sudo cp /var/lib/customdrs/rules.db $BACKUP_DIR/rules-$DATE.db

# Backup configuration
sudo cp /opt/customdrs/publish/appsettings.Production.json $BACKUP_DIR/appsettings-$DATE.json

# Start service
sudo systemctl start customdrs-web

echo "Backup completed: $BACKUP_DIR"
```

### Restore

```bash
#!/bin/bash
# restore-customdrs.sh

if [ -z "$1" ]; then
    echo "Usage: $0 <backup-date>"
    echo "Example: $0 20240215-143022"
    exit 1
fi

DATE=$1
BACKUP_DIR="/backup/customdrs"

# Stop service
sudo systemctl stop customdrs-web

# Restore databases
sudo cp $BACKUP_DIR/identity-$DATE.db /var/lib/customdrs/identity.db
sudo cp $BACKUP_DIR/rules-$DATE.db /var/lib/customdrs/rules.db

# Fix permissions
sudo chown -R $USER:$USER /var/lib/customdrs/

# Start service
sudo systemctl start customdrs-web

echo "Restore completed from: $DATE"
```

## Security

### Password Policy

- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one digit
- At least one special character

### Account Lockout

- Maximum 5 failed attempts
- 15-minute lockout duration
- Automatic unlock after timeout

### Session Security

- 2-hour session timeout
- Sliding expiration (extends with activity)
- Secure HTTP-only cookies
- Anti-forgery tokens on forms

### Database Security

- SQLite databases with file permissions
- Only application user can access
- Regular backups recommended
- Consider encryption for sensitive environments

### Network Security

```bash
# Allow only specific IP
sudo ufw allow from 192.168.1.0/24 to any port 5000

# Or use nginx reverse proxy with SSL
sudo apt-get install nginx certbot python3-certbot-nginx
```

## Firewall Configuration

### UFW (Uncomplicated Firewall)

```bash
# Enable UFW
sudo ufw enable

# Allow SSH (important!)
sudo ufw allow ssh

# Allow HTTP on port 5000
sudo ufw allow 5000/tcp

# Check status
sudo ufw status
```

### iptables

```bash
# Allow port 5000
sudo iptables -A INPUT -p tcp --dport 5000 -j ACCEPT

# Save rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

## Production Setup with nginx + SSL

### Install nginx

```bash
sudo apt-get install nginx
```

### Configure nginx

Create `/etc/nginx/sites-available/customdrs`:

```nginx
server {
    listen 80;
    server_name customdrs.yourdomain.com;

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
```

### Enable site

```bash
sudo ln -s /etc/nginx/sites-available/customdrs /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### Add SSL with Let's Encrypt

```bash
sudo apt-get install certbot python3-certbot-nginx
sudo certbot --nginx -d customdrs.yourdomain.com
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status customdrs-web

# View detailed logs
sudo journalctl -u customdrs-web -n 50 --no-pager

# Common causes:
# 1. Port 5000 already in use
sudo netstat -tlnp | grep 5000

# 2. Missing .NET runtime
dotnet --version

# 3. Database permission issues
ls -l /var/lib/customdrs/
sudo chown -R $USER:$USER /var/lib/customdrs/

# 4. Application file permissions
ls -l /opt/customdrs/publish/
```

### Cannot Connect to Web Interface

```bash
# Check if service is running
sudo systemctl status customdrs-web

# Check if port is listening
sudo netstat -tlnp | grep 5000

# Check firewall
sudo ufw status

# Test locally
curl http://localhost:5000

# Test from network
curl http://YOUR_SERVER_IP:5000
```

### Database Errors

```bash
# Check database files exist
ls -l /var/lib/customdrs/

# Check database integrity
sqlite3 /var/lib/customdrs/rules.db "PRAGMA integrity_check;"

# Reinitialize databases (CAUTION: deletes all data)
sudo systemctl stop customdrs-web
sudo rm /var/lib/customdrs/*.db
sudo systemctl start customdrs-web
# Databases will be recreated with default admin user
```

### Forgot Admin Password

```bash
# Stop service
sudo systemctl stop customdrs-web

# Delete identity database
sudo rm /var/lib/customdrs/identity.db

# Start service
sudo systemctl start customdrs-web

# Default admin will be recreated
# Username: admin
# Password: ChangeMe123!
```

### High CPU/Memory Usage

```bash
# Check resource usage
systemctl status customdrs-web

# Monitor process
top -p $(pgrep -f CustomDRS.Web)

# Check database size
du -h /var/lib/customdrs/

# Optimize database
sqlite3 /var/lib/customdrs/rules.db "VACUUM;"

# Restart service
sudo systemctl restart customdrs-web
```

### Application Updates

```bash
# 1. Backup current version
sudo systemctl stop customdrs-web
sudo tar -czf /backup/customdrs-$(date +%Y%m%d).tar.gz /opt/customdrs /var/lib/customdrs

# 2. Deploy new version
cd /path/to/new/version
./build-and-deploy.sh

# 3. Start service
sudo systemctl start customdrs-web

# 4. Verify
sudo systemctl status customdrs-web
curl http://localhost:5000
```

## Performance Tuning

### Database Optimization

```bash
# Add additional indexes
sqlite3 /var/lib/customdrs/rules.db << EOF
CREATE INDEX IF NOT EXISTS idx_rules_cluster ON AffinityRules(ClusterName);
CREATE INDEX IF NOT EXISTS idx_rules_type ON AffinityRules(RuleType);
CREATE INDEX IF NOT EXISTS idx_rules_enabled_cluster ON AffinityRules(Enabled, ClusterName);
EOF

# Vacuum databases periodically
sqlite3 /var/lib/customdrs/rules.db "VACUUM;"
sqlite3 /var/lib/customdrs/identity.db "VACUUM;"
```

### Application Settings

For high-traffic scenarios, consider:
- Increasing session timeout
- Adjusting connection limits
- Enabling response caching
- Using a reverse proxy (nginx)

## Monitoring

### Health Check Script

```bash
#!/bin/bash
# health-check.sh

# Check if service is running
if ! systemctl is-active --quiet customdrs-web; then
    echo "ERROR: CustomDRS service is not running!"
    sudo systemctl start customdrs-web
    exit 1
fi

# Check if port is responsive
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 | grep -q "200"; then
    echo "WARNING: CustomDRS web interface not responding"
    sudo systemctl restart customdrs-web
    exit 1
fi

echo "OK: CustomDRS is healthy"
exit 0
```

### Automated Monitoring

```bash
# Add to crontab
crontab -e

# Check every 5 minutes
*/5 * * * * /usr/local/bin/health-check.sh >> /var/log/customdrs/health.log 2>&1
```

## FAQ

**Q: Can I run this on Ubuntu instead of Debian?**
A: Yes, the application works on Ubuntu 22.04+ with minimal changes.

**Q: Does this support HTTPS?**
A: Use nginx or Apache as a reverse proxy with SSL/TLS certificates.

**Q: Can multiple users edit rules simultaneously?**
A: Yes, the application handles concurrent access with SQLite locking.

**Q: How do I backup the rules?**
A: Use the backup scripts provided or simply copy the SQLite database files.

**Q: Can I integrate this with vCenter API?**
A: The web UI manages rules in the database. Use PowerShell scripts to apply rules to vCenter.

**Q: What happens if the database gets corrupted?**
A: Use the backup to restore. SQLite is very reliable, but keep regular backups.

**Q: Can I change the default admin username?**
A: Yes, create a new admin user, then delete the default admin.

**Q: How do I add custom themes/branding?**
A: Modify the CSS files in `wwwroot/css/` and views in `Views/Shared/`.

## Additional Resources

- **.NET Documentation**: https://docs.microsoft.com/dotnet/
- **ASP.NET Core**: https://docs.microsoft.com/aspnet/core/
- **SQLite**: https://www.sqlite.org/docs.html
- **Debian**: https://www.debian.org/doc/

## Support

For issues or questions:
1. Check the logs: `sudo journalctl -u customdrs-web -f`
2. Review this guide
3. Check database integrity
4. Verify .NET runtime is installed
5. Ensure firewall allows port 5000

## Changelog

### Version 1.0.0
- Initial release
- User authentication with Identity
- DRS rule CRUD operations
- Dashboard with statistics
- Audit trail and history
- Violation tracking
- Debian 12 support
- SystemD service integration
