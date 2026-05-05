# Copyright (c) 2026 Mud MCP Contributors
# Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

<#
.SYNOPSIS
    Configures an IIS website and application pool.

.DESCRIPTION
    Creates or updates an IIS website and application pool with the specified settings.
    Configures the app pool for ASP.NET Core hosting and ensures the requested
    IIS binding protocol is configured for the deployment port.

.PARAMETER WebsiteName
    The name of the IIS website.

.PARAMETER AppPoolName
    The name of the IIS application pool.

.PARAMETER PhysicalPath
    Physical path for the website.

.PARAMETER Port
    Port for the website binding (default: 8000).

.PARAMETER BindingProtocol
    IIS binding protocol for the website (default: https).

.PARAMETER SslCertificateThumbprint
    Optional certificate thumbprint to assign to the HTTPS binding. If omitted,
    the script falls back to the IIS_SSL_CERTIFICATE_THUMBPRINT environment
    variable. If neither is set, any existing HTTPS certificate binding is
    preserved.

.EXAMPLE
    .\Configure-IisWebsite.ps1 -WebsiteName "MudBlazorMcp" -AppPoolName "MudBlazorMcpPool" -PhysicalPath "C:\inetpub\wwwroot\MudBlazorMcp" -Port 8000 -BindingProtocol https -SslCertificateThumbprint "ABCD1234..."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$WebsiteName,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppPoolName,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PhysicalPath,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 8000,

    [Parameter(Mandatory=$false)]
    [ValidateSet('http', 'https')]
    [string]$BindingProtocol = 'https',

    [Parameter(Mandatory=$false)]
    [string]$SslCertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load shared validation functions
. "$PSScriptRoot\Common\PathValidation.ps1"

# Validate names
Test-IisResourceName -Name $WebsiteName -ResourceType 'website'
Test-IisResourceName -Name $AppPoolName -ResourceType 'app pool'

# Validate and normalize physical path
$PhysicalPath = Get-ValidatedPath -Path $PhysicalPath -ParameterName 'PhysicalPath'
$BindingProtocol = $BindingProtocol.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($SslCertificateThumbprint) -and -not [string]::IsNullOrWhiteSpace($env:IIS_SSL_CERTIFICATE_THUMBPRINT)) {
    $SslCertificateThumbprint = $env:IIS_SSL_CERTIFICATE_THUMBPRINT
}

# If an optional Azure DevOps variable was not defined, the macro can arrive as
# the literal string '$(variableName)'. Treat that as unset.
if ($SslCertificateThumbprint -match '^\$\([^)]+\)$') {
    $SslCertificateThumbprint = $null
}

Import-Module WebAdministration -ErrorAction SilentlyContinue
Import-Module IISAdministration -ErrorAction SilentlyContinue

# Create Application Pool if it doesn't exist
if (-not (Get-IISAppPool -Name $AppPoolName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating application pool: $AppPoolName"
    New-WebAppPool -Name $AppPoolName
}

# Configure Application Pool
Write-Host "Configuring application pool..."
$appPool = Get-Item "IIS:\AppPools\$AppPoolName"
$appPool.managedRuntimeVersion = ""  # No managed code (use .NET Core hosting)
$appPool.startMode = "AlwaysRunning"
$appPool.processModel.idleTimeout = [TimeSpan]::FromMinutes(0)
$appPool | Set-Item

# Create Website if it doesn't exist. New-Website creates an HTTP binding by
# default, so the binding is normalized immediately afterwards.
if (-not (Get-Website -Name $WebsiteName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating website: $WebsiteName"
    New-Website -Name $WebsiteName `
                -PhysicalPath $PhysicalPath `
                -ApplicationPool $AppPoolName `
                -Port $Port
} else {
    # Update existing website
    Write-Host "Updating website: $WebsiteName"
    Set-ItemProperty "IIS:\Sites\$WebsiteName" -Name physicalPath -Value $PhysicalPath
    Set-ItemProperty "IIS:\Sites\$WebsiteName" -Name applicationPool -Value $AppPoolName
}

$desiredBindingInformation = "*:${Port}:"

# Remove any same-port binding using the wrong protocol. This fixes previously
# released HTTP bindings when the desired release binding is HTTPS.
Get-WebBinding -Name $WebsiteName -ErrorAction SilentlyContinue |
Where-Object {
    $parts = $_.bindingInformation -split ':', 3
    $parts.Count -ge 2 -and $parts[1] -eq [string]$Port -and $_.protocol -ne $BindingProtocol
} |
ForEach-Object {
    $parts = $_.bindingInformation -split ':', 3
    $ipAddress = if ([string]::IsNullOrWhiteSpace($parts[0])) { '*' } else { $parts[0] }
    $hostHeader = if ($parts.Count -ge 3) { $parts[2] } else { '' }

    Write-Host "Removing $($_.protocol) binding on port $Port for website: $WebsiteName"
    Remove-WebBinding -Name $WebsiteName -Protocol $_.protocol -IPAddress $ipAddress -Port $Port -HostHeader $hostHeader
}

$desiredBinding = Get-WebBinding -Name $WebsiteName -Protocol $BindingProtocol -ErrorAction SilentlyContinue |
    Where-Object { $_.bindingInformation -eq $desiredBindingInformation } |
    Select-Object -First 1

if (-not $desiredBinding) {
    Write-Host "Creating $BindingProtocol binding on port $Port for website: $WebsiteName"
    New-WebBinding -Name $WebsiteName -Protocol $BindingProtocol -IPAddress '*' -Port $Port
    $desiredBinding = Get-WebBinding -Name $WebsiteName -Protocol $BindingProtocol -ErrorAction SilentlyContinue |
        Where-Object { $_.bindingInformation -eq $desiredBindingInformation } |
        Select-Object -First 1
} else {
    Write-Host "Binding already configured: $BindingProtocol on port $Port"
}

if ($BindingProtocol -eq 'https') {
    if (-not [string]::IsNullOrWhiteSpace($SslCertificateThumbprint)) {
        $normalizedThumbprint = ($SslCertificateThumbprint -replace '\s', '').ToUpperInvariant()
        $certificate = Get-ChildItem -Path Cert:\LocalMachine\My |
            Where-Object { $_.Thumbprint -eq $normalizedThumbprint } |
            Select-Object -First 1

        if (-not $certificate) {
            throw "SSL certificate with thumbprint '$normalizedThumbprint' was not found in Cert:\LocalMachine\My."
        }

        if (-not $desiredBinding) {
            throw "Could not locate HTTPS binding for '$WebsiteName' on port $Port after creating it."
        }

        $desiredBinding.AddSslCertificate($normalizedThumbprint, 'My')
        Write-Host "Assigned SSL certificate to HTTPS binding."
    } else {
        Write-Warning "HTTPS binding configured without a certificate thumbprint. Existing certificate binding, if any, was preserved."
    }
}

Write-Host "IIS configuration completed."
exit 0
