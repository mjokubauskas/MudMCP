# Engineering Folder

This folder contains Azure DevOps pipeline configurations for building, testing, and deploying the MudBlazor MCP Server.

## Pipeline Structure

```
eng/
├── azure-pipelines.yaml          # Main pipeline definition
├── templates/
│   ├── deploy-iis-stage.yaml     # Reusable environment deployment stage template
│   └── deploy-iis.yaml           # Reusable IIS deployment step template
├── scripts/                      # PowerShell deployment scripts
│   ├── Stop-IisSiteAndAppPool.ps1
│   ├── Backup-Deployment.ps1
│   ├── Deploy-IisContent.ps1
│   ├── Configure-IisWebsite.ps1
│   ├── Update-EnvironmentSettings.ps1
│   ├── Set-IisFolderPermissions.ps1
│   ├── Start-IisSiteAndAppPool.ps1
│   ├── Test-DeploymentHealth.ps1
│   └── Prepare-IisConfiguration.ps1
└── README.md                     # This file
```

## Pipeline Overview

The pipeline consists of build validation plus shared IIS deployment stages:

### 1. Build Stage
- Restores NuGet packages (with caching)
- Builds the solution in Release configuration
- Runs unit tests with code coverage
- Publishes the application
- Creates deployment artifact

### 2. Deploy to Development
- Triggers on `develop` branch
- Deploys to `mudblazor-mcp-dev` environment
- Uses the shared IIS deployment stage and step templates

### 3. Deploy to Test
- Triggers on `main` branch after Build
- Deploys to `mudblazor-mcp-test` environment
- Uses `ASPNETCORE_ENVIRONMENT=Staging`
- Uses the same IIS deployment configuration as development and production

### 4. Deploy to Production
- Triggers on `main` branch
- Runs after the Test deployment succeeds
- Deploys to `mudblazor-mcp-prod` environment
- Includes health checks and rollback notifications
- Uses the same IIS deployment configuration as development and test

## Prerequisites

### Azure DevOps Setup

1. **Create Environments**:
    - Go to Pipelines → Environments
    - Create `mudblazor-mcp-dev` for development
    - Create `mudblazor-mcp-test` for test
    - Create `mudblazor-mcp-prod` for production (with approval gates)

2. **Register VM as Deployment Target**:
   - In each environment, click "Add resource" → "Virtual machines"
   - Follow the registration script for your Windows VM
   - **Important**: The agent pool name used during VM registration must match your environment configuration
   - Deployment jobs use environment-registered agents (no explicit pool specified in YAML)
   - Ensure the VM has:
     - IIS installed with ASP.NET Core Hosting Bundle
     - .NET 10 Runtime
     - PowerShell 5.1+

3. **Configure Service Connections** (if using Azure resources):
   - Go to Project Settings → Service connections
   - Create connections for any Azure resources needed

### VM Requirements

The target VM must have:

```powershell
# Install IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# Install ASP.NET Core Hosting Bundle
# Download from: https://dotnet.microsoft.com/download/dotnet/10.0

# Verify installation
Get-WindowsFeature Web-Server
dotnet --list-runtimes
```

## Deployment Scripts

The `eng/scripts/` directory contains PowerShell scripts used by the deployment pipeline. These scripts are version-controlled and reviewed to ensure security and reliability.

### Script Overview

| Script | Purpose |
|--------|---------|
| `Prepare-IisConfiguration.ps1` | Creates web.config and logs directory during build |
| `Stop-IisSiteAndAppPool.ps1` | Gracefully stops IIS app pool before deployment |
| `Backup-Deployment.ps1` | Creates timestamped backup with retention policy |
| `Deploy-IisContent.ps1` | Copies application files to IIS physical path |
| `Configure-IisWebsite.ps1` | Creates/updates IIS website and app pool |
| `Update-EnvironmentSettings.ps1` | Updates web.config environment variables |
| `Set-IisFolderPermissions.ps1` | Configures file system ACLs |
| `Start-IisSiteAndAppPool.ps1` | Starts IIS app pool and website |
| `Test-DeploymentHealth.ps1` | Verifies deployment with health checks and diagnostics |

### Script Security Features

All deployment scripts implement hardening measures:
- **Input validation**: Parameters use `[ValidateNotNullOrEmpty()]`, `[ValidateRange()]`, and `[ValidateSet()]`
- **Path validation**: Physical paths restricted to allowed roots (`C:\inetpub`, `C:\WWW`, `D:\WWW`)
- **Name validation**: IIS names restricted to alphanumeric characters, underscores, and hyphens
- **Path traversal protection**: Blocks `..` and invalid characters in paths
- **Strict mode**: Scripts use `Set-StrictMode -Version Latest`
- **Error handling**: Proper `$ErrorActionPreference` settings
- **No secrets**: Scripts never log sensitive data

### Using Scripts Locally

Scripts can be executed manually for troubleshooting:

```powershell
# Stop app pool
.\eng\scripts\Stop-IisSiteAndAppPool.ps1 -AppPoolName "MudBlazorMcpPool"

# Create backup
.\eng\scripts\Backup-Deployment.ps1 -PhysicalPath "C:\inetpub\wwwroot\MudBlazorMcp"

# Test health
.\eng\scripts\Test-DeploymentHealth.ps1 -Port 8000 -AppPoolName "MudBlazorMcpPool" -PhysicalPath "C:\inetpub\wwwroot\MudBlazorMcp"
```

## Configuration

### Pipeline Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `buildConfiguration` | Build configuration | `Release` |
| `dotnetVersion` | .NET SDK version | `10.x` |
| `iisWebsiteName` | IIS website name | `MudBlazorMcp` |
| `iisAppPoolName` | IIS app pool name | `MudBlazorMcpPool` |
| `iisPhysicalPath` | Deployment path | `C:\inetpub\wwwroot\MudBlazorMcp` |
| `iisPort` | IIS website HTTP port | `8000` |
| `deploymentHealthMaxRetries` | Health check retry count | `6` |
| `deploymentHealthRetryDelaySeconds` | Delay between health check retries | `10` |
| `mudBlazorVersion` | MudBlazor docs version served by the MCP server | `9.0.0` |

### Environment-Specific Settings

Dev, test, and production share the same IIS deployment settings from the pipeline variables above and the same deployment lifecycle from `eng/templates/deploy-iis-stage.yaml`. Only the Azure DevOps environment name and `ASPNETCORE_ENVIRONMENT` value differ by environment.

If a server needs environment-specific application settings, create the appropriate `appsettings.{Environment}.json` file on that server. The deployment preserves server-managed `appsettings.*.json` files. For example, production can use `appsettings.Production.json`:

```json
{
  "MudBlazor": {
    "Repository": {
      "LocalPath": "C:\\ProgramData\\MudBlazorMcp\\mudblazor-repo"
    }
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
```

## Running the Pipeline

### Automatic Triggers

- **Develop branch**: Triggers Build + Deploy to Dev
- **Main branch**: Triggers Build + Deploy to Test + Deploy to Production

### Manual Run

1. Go to Pipelines → Select the pipeline
2. Click "Run pipeline"
3. Select branch
4. Click "Run"

## Troubleshooting

### Common Issues

**App pool won't start**:
```powershell
# Check event log
Get-EventLog -LogName System -Source "IIS*" -Newest 10
```

**Health check fails**:
```powershell
# Check if app is listening
netstat -an | Select-String "8000"

# Check application logs
Get-Content "C:\inetpub\wwwroot\MudBlazorMcp\logs\stdout*.log" -Tail 50
```

**Permission issues**:
```powershell
# Grant minimal required permissions
$sitePath = "C:\inetpub\wwwroot\MudBlazorMcp"
$appPoolIdentity = "IIS AppPool\MudBlazorMcpPool"

# Read/Execute on site root
$acl = Get-Acl $sitePath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $appPoolIdentity, "ReadAndExecute,Synchronize", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($rule)
Set-Acl $sitePath $acl

# Modify on logs and data directories only
foreach ($dir in @("logs", "data")) {
    $subPath = Join-Path $sitePath $dir
    if (-not (Test-Path $subPath)) { New-Item -ItemType Directory -Path $subPath -Force }
    $subAcl = Get-Acl $subPath
    $writeRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $appPoolIdentity, "Modify,Synchronize", "ContainerInherit,ObjectInherit", "None", "Allow")
    $subAcl.SetAccessRule($writeRule)
    Set-Acl -Path $subPath -AclObject $subAcl
}
```

## Security Considerations

- Use Azure Key Vault for sensitive configuration
- Configure approval gates for production deployments
- Restrict VM access to deployment service accounts
- Enable IIS request logging for audit trails
- Use HTTPS in production with valid SSL certificates

### Deployment Scripts Security

All deployment scripts in `eng/scripts/` implement security hardening:
- Input validation using parameter whitelists and allowed path roots
- Protection against path traversal attacks
- Strict mode and error handling
- No sensitive data logging
- Clear parameter definitions with mandatory/optional attributes

**IMPORTANT**: All changes to deployment scripts and pipeline configurations in `eng/` require code review by repository maintainers (enforced via `.github/CODEOWNERS`).
