# Copyright (c) 2026 Mud MCP Contributors
# Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

<#
.SYNOPSIS
    Updates the ASP.NET Core environment setting in web.config.

.DESCRIPTION
    Modifies the web.config file to set the ASPNETCORE_ENVIRONMENT variable.
    Optionally sets the MUDBLAZOR_VERSION environment variable used by the
    MCP server to determine which MudBlazor documentation version to serve.

.PARAMETER PhysicalPath
    Physical path where web.config is located.

.PARAMETER Environment
    ASP.NET Core environment name (e.g., Development, Staging, Production).

.PARAMETER MudBlazorVersion
    Optional MudBlazor version (e.g., 9.0.0 or 9.0.0-preview.1) to set as the
    MUDBLAZOR_VERSION environment variable in web.config. Must match the format
    X.Y.Z or X.Y.Z-prerelease. Whitespace-only values are ignored.

.EXAMPLE
    .\Update-EnvironmentSettings.ps1 -PhysicalPath "C:\inetpub\wwwroot\MudBlazorMcp" -Environment "Production"

.EXAMPLE
    .\Update-EnvironmentSettings.ps1 -PhysicalPath "C:\inetpub\wwwroot\MudBlazorMcp" -Environment "Production" -MudBlazorVersion "9.0.0"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PhysicalPath,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('Development', 'Staging', 'Production')]
    [string]$Environment,

    [Parameter(Mandatory=$false)]
    [string]$MudBlazorVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load shared validation functions
. "$PSScriptRoot\Common\PathValidation.ps1"

# Validate and normalize physical path
$PhysicalPath = Get-ValidatedPath -Path $PhysicalPath -ParameterName 'PhysicalPath'

$webConfigPath = Join-Path $PhysicalPath "web.config"

if (Test-Path $webConfigPath) {
    Write-Host "Updating web.config for environment: $Environment"
    
    [xml]$webConfig = Get-Content $webConfigPath
    
    # Find or create environmentVariables section
    $aspNetCore = $webConfig.SelectSingleNode("/*[local-name()='configuration']/*[local-name()='location']/*[local-name()='system.webServer']/*[local-name()='aspNetCore']")
    if ($aspNetCore) {
        # Use SelectSingleNode to safely check for environmentVariables (avoids strict mode errors)
        $envVars = $aspNetCore.SelectSingleNode("environmentVariables")
        if (-not $envVars) {
            $envVars = $webConfig.CreateElement("environmentVariables")
            $aspNetCore.AppendChild($envVars) | Out-Null
        }
        
        # Update or add ASPNETCORE_ENVIRONMENT
        $envVar = $envVars.SelectSingleNode("environmentVariable[@name='ASPNETCORE_ENVIRONMENT']")
        if ($envVar) {
            $envVar.SetAttribute("value", $Environment)
        } else {
            $newEnvVar = $webConfig.CreateElement("environmentVariable")
            $newEnvVar.SetAttribute("name", "ASPNETCORE_ENVIRONMENT")
            $newEnvVar.SetAttribute("value", $Environment)
            $envVars.AppendChild($newEnvVar) | Out-Null
        }
        
        # Update or add MUDBLAZOR_VERSION if specified and non-whitespace
        if (-not [string]::IsNullOrWhiteSpace($MudBlazorVersion)) {
            $mudBlazorVersionTrimmed = $MudBlazorVersion.Trim()
            # Validate MudBlazor version format: X.Y.Z or X.Y.Z-prerelease
            if ($mudBlazorVersionTrimmed -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$') {
                throw "Invalid MudBlazorVersion '$MudBlazorVersion'. Expected format 'X.Y.Z' or 'X.Y.Z-prerelease'."
            }
            $mudVar = $envVars.SelectSingleNode("environmentVariable[@name='MUDBLAZOR_VERSION']")
            if ($mudVar) {
                $mudVar.SetAttribute("value", $mudBlazorVersionTrimmed)
            } else {
                $newMudVar = $webConfig.CreateElement("environmentVariable")
                $newMudVar.SetAttribute("name", "MUDBLAZOR_VERSION")
                $newMudVar.SetAttribute("value", $mudBlazorVersionTrimmed)
                $envVars.AppendChild($newMudVar) | Out-Null
            }
            Write-Host "Set MUDBLAZOR_VERSION to $mudBlazorVersionTrimmed"
        }

        $webConfig.Save($webConfigPath)
        Write-Host "web.config updated successfully."
    } else {
        Write-Warning "Could not find aspNetCore section in web.config"
    }
} else {
    Write-Warning "web.config not found at: $webConfigPath"
}

exit 0
