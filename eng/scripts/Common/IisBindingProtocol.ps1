# Copyright (c) 2026 Mud MCP Contributors
# Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

function Get-NormalizedIisSslCertificateThumbprint {
    <#
    .SYNOPSIS
        Gets the first meaningful SSL certificate thumbprint from explicit or environment input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$SslCertificateThumbprint,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$EnvironmentThumbprint = $env:IIS_SSL_CERTIFICATE_THUMBPRINT
    )

    foreach ($candidate in @($SslCertificateThumbprint, $EnvironmentThumbprint)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $trimmedCandidate = $candidate.Trim()

        # Optional Azure DevOps variables can arrive unresolved as literal macros.
        if ($trimmedCandidate -match '^\$\([^)]+\)$') {
            continue
        }

        return ($trimmedCandidate -replace '\s', '').ToUpperInvariant()
    }

    return $null
}

function Test-IisHttpsBindingHasCertificate {
    <#
    .SYNOPSIS
        Checks whether an IIS HTTPS binding already has a certificate hash.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        $Binding
    )

    if ($null -eq $Binding) {
        return $false
    }

    try {
        $certificateHash = $Binding.certificateHash
    } catch {
        $certificateHash = $null
    }

    if ($null -eq $certificateHash) {
        return $false
    }

    if ($certificateHash -is [byte[]]) {
        return $certificateHash.Length -gt 0
    }

    return -not [string]::IsNullOrWhiteSpace([string]$certificateHash)
}

function Resolve-IisBindingProtocol {
    <#
    .SYNOPSIS
        Resolves the requested IIS binding protocol to the effective protocol.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('auto', 'http', 'https')]
        [string]$BindingProtocol = 'auto',

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$NormalizedSslCertificateThumbprint,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        $ExistingHttpsBinding,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$WebsiteName,

        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 65535)]
        [int]$Port
    )

    $requestedProtocol = $BindingProtocol.ToLowerInvariant()
    $hasThumbprint = -not [string]::IsNullOrWhiteSpace($NormalizedSslCertificateThumbprint)
    $hasExistingHttpsCertificate = Test-IisHttpsBindingHasCertificate -Binding $ExistingHttpsBinding

    if ($requestedProtocol -eq 'http') {
        return 'http'
    }

    if ($requestedProtocol -eq 'https') {
        if ($hasThumbprint -or $hasExistingHttpsCertificate) {
            return 'https'
        }

        throw "HTTPS binding for '$WebsiteName' on port $Port requires a value for the SslCertificateThumbprint parameter or an existing HTTPS binding with a certificate. To deploy without a certificate, set BindingProtocol to auto or http."
    }

    if ($hasThumbprint -or $hasExistingHttpsCertificate) {
        return 'https'
    }

    return 'http'
}
