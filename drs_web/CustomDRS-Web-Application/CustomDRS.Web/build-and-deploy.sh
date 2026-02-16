#!/bin/bash

# CustomDRS Web Application - Build and Deploy Script for Debian 12
# Requires .NET 8 SDK to build, .NET 8 Runtime to run

set -e

echo "=========================================="
echo "CustomDRS Web Application"
echo "Build and Deployment Script for Debian 12"
echo "=========================================="
echo ""

# Check if .NET SDK is installed
if ! command -v dotnet &> /dev/null; then
    echo "ERROR: .NET SDK not found!"
    echo "Please install .NET 8 SDK first:"
    echo ""
    echo "wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh"
    echo "chmod +x dotnet-install.sh"
    echo "./dotnet-install.sh --channel 8.0"
    echo ""
    exit 1
fi

# Check .NET version
DOTNET_VERSION=$(dotnet --version)
echo "✓ .NET SDK found: $DOTNET_VERSION"

# Create necessary directories
echo ""
echo "Creating directories..."
sudo mkdir -p /var/lib/customdrs
sudo mkdir -p /var/log/customdrs
sudo mkdir -p /opt/customdrs

# Set permissions
sudo chown -R $USER:$USER /var/lib/customdrs
sudo chown -R $USER:$USER /var/log/customdrs
sudo chown -R $USER:$USER /opt/customdrs

echo "✓ Directories created"

# Build the application
echo ""
echo "Building application..."
dotnet build -c Release

echo "✓ Build completed"

# Publish the application
echo ""
echo "Publishing application..."
dotnet publish -c Release -o /opt/customdrs/publish

echo "✓ Application published to /opt/customdrs/publish"

# Create appsettings.Production.json if it doesn't exist
if [ ! -f /opt/customdrs/publish/appsettings.Production.json ]; then
    echo ""
    echo "Creating production configuration..."
    cat > /opt/customdrs/publish/appsettings.Production.json << 'EOF'
{
  "ConnectionStrings": {
    "IdentityConnection": "Data Source=/var/lib/customdrs/identity.db",
    "DRSRulesConnection": "Data Source=/var/lib/customdrs/rules.db"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    },
    "Console": {
      "IncludeScopes": true
    },
    "File": {
      "Path": "/var/log/customdrs/app.log",
      "Append": true,
      "MinLevel": "Information"
    }
  },
  "AllowedHosts": "*"
}
EOF
    echo "✓ Production configuration created"
fi

# Create systemd service file
echo ""
echo "Creating systemd service..."
sudo cat > /etc/systemd/system/customdrs-web.service << 'EOF'
[Unit]
Description=CustomDRS Web Application
After=network.target

[Service]
Type=notify
User=$USER
WorkingDirectory=/opt/customdrs/publish
ExecStart=/usr/bin/dotnet /opt/customdrs/publish/CustomDRS.Web.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=customdrs-web
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

[Install]
WantedBy=multi-user.target
EOF

# Replace $USER with actual username
sudo sed -i "s/\$USER/$USER/g" /etc/systemd/system/customdrs-web.service

echo "✓ Systemd service created"

# Reload systemd
echo ""
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Enable and start service
echo "Enabling service..."
sudo systemctl enable customdrs-web.service

echo ""
echo "=========================================="
echo "Build and deployment completed!"
echo "=========================================="
echo ""
echo "To start the application:"
echo "  sudo systemctl start customdrs-web"
echo ""
echo "To check status:"
echo "  sudo systemctl status customdrs-web"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u customdrs-web -f"
echo ""
echo "Application will be available at:"
echo "  http://localhost:5000"
echo "  http://YOUR_SERVER_IP:5000"
echo ""
echo "Default login credentials:"
echo "  Username: admin"
echo "  Email: admin@customdrs.local"
echo "  Password: ChangeMe123!"
echo ""
echo "IMPORTANT: Change the default password immediately after first login!"
echo ""
echo "Database files location:"
echo "  Identity DB: /var/lib/customdrs/identity.db"
echo "  DRS Rules DB: /var/lib/customdrs/rules.db"
echo ""
echo "Log files location:"
echo "  /var/log/customdrs/"
echo ""
