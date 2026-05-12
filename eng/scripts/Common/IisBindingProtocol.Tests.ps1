# Copyright (c) 2026 Mud MCP Contributors
# Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

BeforeAll {
    . "$PSScriptRoot\IisBindingProtocol.ps1"
}

Describe 'Get-NormalizedIisSslCertificateThumbprint' {
    It 'Uses the explicit thumbprint before the environment value' {
        $thumbprint = Get-NormalizedIisSslCertificateThumbprint `
            -SslCertificateThumbprint ' ab cd 12 ' `
            -EnvironmentThumbprint 'FFFF'

        $thumbprint | Should -Be 'ABCD12'
    }

    It 'Uses the environment thumbprint when the explicit thumbprint is empty' {
        $thumbprint = Get-NormalizedIisSslCertificateThumbprint `
            -SslCertificateThumbprint '' `
            -EnvironmentThumbprint ' ef 34 '

        $thumbprint | Should -Be 'EF34'
    }

    It 'Treats unresolved Azure DevOps variables as unset' {
        $thumbprint = Get-NormalizedIisSslCertificateThumbprint `
            -SslCertificateThumbprint '$(iisDevSslCertificateThumbprint)' `
            -EnvironmentThumbprint '$(iisFallbackSslCertificateThumbprint)'

        $thumbprint | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-IisBindingProtocol' {
    It 'Selects HTTPS in auto mode when a thumbprint parameter is supplied' {
        $thumbprint = Get-NormalizedIisSslCertificateThumbprint `
            -SslCertificateThumbprint 'ab cd 12' `
            -EnvironmentThumbprint ''

        $protocol = Resolve-IisBindingProtocol `
            -BindingProtocol 'auto' `
            -NormalizedSslCertificateThumbprint $thumbprint `
            -ExistingHttpsBinding $null `
            -WebsiteName 'MudBlazorMcp' `
            -Port 8000

        $protocol | Should -Be 'https'
    }

    It 'Selects HTTPS in auto mode when an environment thumbprint is supplied' {
        $thumbprint = Get-NormalizedIisSslCertificateThumbprint `
            -SslCertificateThumbprint '' `
            -EnvironmentThumbprint '12 34 ab'

        $protocol = Resolve-IisBindingProtocol `
            -BindingProtocol 'auto' `
            -NormalizedSslCertificateThumbprint $thumbprint `
            -ExistingHttpsBinding $null `
            -WebsiteName 'MudBlazorMcp' `
            -Port 8000

        $protocol | Should -Be 'https'
    }

    It 'Selects HTTP in auto mode when there is no thumbprint or existing HTTPS certificate' {
        $protocol = Resolve-IisBindingProtocol `
            -BindingProtocol 'auto' `
            -NormalizedSslCertificateThumbprint $null `
            -ExistingHttpsBinding $null `
            -WebsiteName 'MudBlazorMcp' `
            -Port 8000

        $protocol | Should -Be 'http'
    }

    It 'Treats unresolved Azure DevOps thumbprint literals as unset in auto mode' {
        $thumbprint = Get-NormalizedIisSslCertificateThumbprint `
            -SslCertificateThumbprint '$(iisDevSslCertificateThumbprint)' `
            -EnvironmentThumbprint ''

        $protocol = Resolve-IisBindingProtocol `
            -BindingProtocol 'auto' `
            -NormalizedSslCertificateThumbprint $thumbprint `
            -ExistingHttpsBinding $null `
            -WebsiteName 'MudBlazorMcp' `
            -Port 8000

        $protocol | Should -Be 'http'
    }

    It 'Selects HTTPS in auto mode when the existing HTTPS binding has a certificate' {
        $existingBinding = [pscustomobject]@{ certificateHash = [byte[]](1, 2, 3) }

        $protocol = Resolve-IisBindingProtocol `
            -BindingProtocol 'auto' `
            -NormalizedSslCertificateThumbprint $null `
            -ExistingHttpsBinding $existingBinding `
            -WebsiteName 'MudBlazorMcp' `
            -Port 8000

        $protocol | Should -Be 'https'
    }

    It 'Keeps explicit HTTP even when an HTTPS certificate exists' {
        $existingBinding = [pscustomobject]@{ certificateHash = [byte[]](1, 2, 3) }

        $protocol = Resolve-IisBindingProtocol `
            -BindingProtocol 'http' `
            -NormalizedSslCertificateThumbprint $null `
            -ExistingHttpsBinding $existingBinding `
            -WebsiteName 'MudBlazorMcp' `
            -Port 8000

        $protocol | Should -Be 'http'
    }

    It 'Fails explicit HTTPS when there is no thumbprint or existing HTTPS certificate' {
        {
            Resolve-IisBindingProtocol `
                -BindingProtocol 'https' `
                -NormalizedSslCertificateThumbprint $null `
                -ExistingHttpsBinding $null `
                -WebsiteName 'MudBlazorMcp' `
                -Port 8000
        } | Should -Throw '*requires a value for the SslCertificateThumbprint parameter or an existing HTTPS binding with a certificate*'
    }
}
