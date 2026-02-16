FROM mcr.microsoft.com/dotnet/sdk:8.0-bookworm-slim AS builder

WORKDIR /build

# Create a dummy project to fetch SQLite and its native Linux dependencies
RUN dotnet new console -n SqliteFetcher && \
    cd SqliteFetcher && \
    dotnet add package System.Data.SQLite.Core && \
    dotnet publish -c Release -r linux-x64 --self-contained false -o /app/sqlite-dist



# Debian 12 (Bookworm) base
FROM debian:bookworm-slim

ENV TZ=UTC

# Switch the default shell from /bin/sh to /bin/bash
SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    ca-certificates \
    vim \
    supervisor \
    tzdata \
    bash \
    wget \
    sqlite3 \
    ssmtp \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

RUN source /usr/lib/os-release && \
    wget -q https://packages.microsoft.com/config/debian/$VERSION_ID/packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm -f packages-microsoft-prod.deb && \
    apt-get update  && apt-get install -y --no-install-recommends powershell dotnet-runtime-8.0

RUN /usr/bin/pwsh -Command '$ErrorActionPreference = "Stop"; Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted; Install-Module -Name VCF.PowerCLI -Scope AllUsers -Force -AllowClobber; Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false; Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false'

# Copy the SQLite DLLs from the Builder stage
WORKDIR /data
COPY --from=builder /app/sqlite-dist .

# Create working directory for logs and input files
WORKDIR /data

# Copy the runner and entrypoint scripts
COPY runner.sh /usr/local/bin/runner.sh
COPY supervisor.conf /data/supervisor.conf
COPY entrypoint.sh /entrypoint.sh
RUN mkdir -p /data/doc /usr/local/share/powershell/Modules/CustomDRS
COPY *.ps1 .
COPY *.md /data/doc
COPY profile.ps1 /opt/microsoft/powershell/7/profile.ps1
COPY CustomDRS.psm1 /usr/local/share/powershell/Modules/CustomDRS/CustomDRS.psm1
RUN chmod +x /usr/local/bin/runner.sh /entrypoint.sh

# Start the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
