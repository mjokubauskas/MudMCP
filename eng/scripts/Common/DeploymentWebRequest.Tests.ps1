# Copyright (c) 2026 Mud MCP Contributors
# Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

BeforeAll {
    . "$PSScriptRoot\DeploymentWebRequest.ps1"
}

Describe 'Invoke-DeploymentHealthRequest' {
    BeforeEach {
        $script:originalCertificateValidationCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        $script:validationResultForTarget = $null
        $script:validationResultForRemote = $null
        $script:callbackDuringRequest = $null
    }

    AfterEach {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $script:originalCertificateValidationCallback
    }

    It 'Allows certificate errors only for the target loopback HTTPS request' {
        Mock Invoke-WebRequest {
            $script:callbackDuringRequest = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            $loopbackRequest = [System.Net.WebRequest]::Create([Uri]'https://localhost:8000/health')
            $remoteRequest = [System.Net.WebRequest]::Create([Uri]'https://example.com/health')

            $script:validationResultForTarget = $script:callbackDuringRequest.Invoke(
                $loopbackRequest,
                $null,
                $null,
                [System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors)

            $script:validationResultForRemote = $script:callbackDuringRequest.Invoke(
                $remoteRequest,
                $null,
                $null,
                [System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors)

            [pscustomobject]@{ StatusCode = 200; Content = 'Healthy' }
        }

        $response = Invoke-DeploymentHealthRequest -Uri ([Uri]'https://localhost:8000/health') -TimeoutSec 7 -SkipCertificateValidation

        $response.StatusCode | Should -Be 200
        $script:validationResultForTarget | Should -BeTrue
        $script:validationResultForRemote | Should -BeFalse
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback | Should -Be $null
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
            $Uri.AbsoluteUri -eq 'https://localhost:8000/health' -and $TimeoutSec -eq 7
        }
    }

    It 'Does not install a certificate callback when bypass is not requested' {
        Mock Invoke-WebRequest {
            $script:callbackDuringRequest = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [pscustomobject]@{ StatusCode = 200; Content = 'Healthy' }
        }

        $response = Invoke-DeploymentHealthRequest -Uri ([Uri]'https://localhost:8000/health')

        $response.StatusCode | Should -Be 200
        $script:callbackDuringRequest | Should -Be $null
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback | Should -Be $null
    }

    It 'Restores the certificate callback when the request throws' {
        Mock Invoke-WebRequest {
            $script:callbackDuringRequest = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            throw 'Network failure'
        }

        { Invoke-DeploymentHealthRequest -Uri ([Uri]'https://localhost:8000/health') -SkipCertificateValidation } |
            Should -Throw '*Network failure*'

        $script:callbackDuringRequest | Should -Not -Be $null
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback | Should -Be $null
    }
}