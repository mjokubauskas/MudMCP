# Copyright (c) 2026 Mud MCP Contributors
# Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

function Invoke-DeploymentHealthRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [Uri]$Uri,

        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSec = 10,

        [Parameter(Mandatory=$false)]
        [switch]$SkipCertificateValidation
    )

    $useCertificateValidationBypass = $SkipCertificateValidation -and $Uri.Scheme -eq 'https' -and $Uri.IsLoopback
    $previousSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    $previousCertificateValidationCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    $targetUri = $Uri

    try {
        if ($Uri.Scheme -eq 'https') {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        }

        if ($useCertificateValidationBypass) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
                param($sender, $certificate, $chain, $sslPolicyErrors)

                if ($sender -is [System.Net.HttpWebRequest] -and
                    $sender.RequestUri.Scheme -eq $targetUri.Scheme -and
                    $sender.RequestUri.Authority -eq $targetUri.Authority -and
                    $sender.RequestUri.IsLoopback) {
                    return $true
                }

                if ($previousCertificateValidationCallback) {
                    return $previousCertificateValidationCallback.Invoke($sender, $certificate, $chain, $sslPolicyErrors)
                }

                return $sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None
            }
        }

        return Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec
    } finally {
        if ($useCertificateValidationBypass) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCertificateValidationCallback
        }

        if ($Uri.Scheme -eq 'https') {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
        }
    }
}