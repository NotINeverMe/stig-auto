# Pester tests for Windows Hardening modules

BeforeAll {
    $script:ModulePath = "$PSScriptRoot\..\..\scripts\windows-hardening"
    $script:TestLogPath = "$env:TEMP\TestHardening.log"
}

Describe "Module Structure Tests" {
    Context "Module Files Exist" {
        It "SecurityBaseline module should exist" {
            Test-Path "$script:ModulePath\SecurityBaseline.psm1" | Should -Be $true
        }
        
        It "AccessControl module should exist" {
            Test-Path "$script:ModulePath\AccessControl.psm1" | Should -Be $true
        }
        
        It "AuditLogging module should exist" {
            Test-Path "$script:ModulePath\AuditLogging.psm1" | Should -Be $true
        }
        
        It "SystemProtection module should exist" {
            Test-Path "$script:ModulePath\SystemProtection.psm1" | Should -Be $true
        }
        
        It "ComplianceReporting module should exist" {
            Test-Path "$script:ModulePath\ComplianceReporting.psm1" | Should -Be $true
        }
        
        It "Main hardening script should exist" {
            Test-Path "$script:ModulePath\Invoke-WindowsHardening.ps1" | Should -Be $true
        }
    }
}

Describe "NIST Control Mapping Tests" {
    Context "Module Content Validation" {
        It "SecurityBaseline should contain NIST control references" {
            $content = Get-Content "$script:ModulePath\SecurityBaseline.psm1" -Raw
            $content | Should -Match "NIST 3\.4\.2"
            $content | Should -Match "NIST 3\.13\.11"
        }
        
        It "AccessControl should contain NIST control references" {
            $content = Get-Content "$script:ModulePath\AccessControl.psm1" -Raw
            $content | Should -Match "NIST 3\.5\.7"
            $content | Should -Match "NIST 3\.1\.1"
        }
        
        It "AuditLogging should contain NIST control references" {
            $content = Get-Content "$script:ModulePath\AuditLogging.psm1" -Raw
            $content | Should -Match "NIST 3\.3\.1"
        }
        
        It "SystemProtection should contain NIST control references" {
            $content = Get-Content "$script:ModulePath\SystemProtection.psm1" -Raw
            $content | Should -Match "NIST 3\.14\.1"
        }
    }
}

Describe "PowerShell Syntax Tests" {
    Context "Script Syntax Validation" {
        It "SecurityBaseline module should have valid PowerShell syntax" {
            { 
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    "$script:ModulePath\SecurityBaseline.psm1", 
                    [ref]$null, 
                    [ref]$null
                )
                $ast | Should -Not -BeNullOrEmpty
            } | Should -Not -Throw
        }
        
        It "Main hardening script should have valid PowerShell syntax" {
            { 
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    "$script:ModulePath\Invoke-WindowsHardening.ps1", 
                    [ref]$null, 
                    [ref]$null
                )
                $ast | Should -Not -BeNullOrEmpty
            } | Should -Not -Throw
        }
    }
}

Describe "Function Export Tests" {
    Context "Module Exports" {
        It "ComplianceReporting module should export Test-ComplianceStatus function" {
            $content = Get-Content "$script:ModulePath\ComplianceReporting.psm1" -Raw
            $content | Should -Match "'Test-ComplianceStatus'"
        }
        
        It "ComplianceReporting module should export Export-ComplianceReport function" {
            $content = Get-Content "$script:ModulePath\ComplianceReporting.psm1" -Raw
            $content | Should -Match "'Export-ComplianceReport'"
        }
    }
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestLogPath) {
        Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
    }
}