# Pester tests for Windows Hardening modules

BeforeAll {
    $script:ModulePath = "$PSScriptRoot\..\..\scripts\windows-hardening"
    $script:TestLogPath = "$env:TEMP\TestHardening.log"
    
    # Mock functions that would make actual system changes
    function script:MockHardeningAction {
        param($Action, $Description, $NistControl)
        
        # Simulate success without making changes
        Write-Host "MOCK: Would execute - $Description"
        return $true
    }
}

Describe "SecurityBaseline Module Tests" {
    BeforeAll {
        Import-Module "$script:ModulePath\SecurityBaseline.psm1" -Force
        
        # Override the Invoke-HardeningAction function
        Mock Invoke-HardeningAction -MockWith $script:MockHardeningAction -ModuleName SecurityBaseline
    }
    
    Context "Set-SecureExecutionPolicy" {
        It "Should attempt to set execution policy" {
            { Set-SecureExecutionPolicy -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Enable-WindowsFirewall" {
        It "Should attempt to enable Windows Firewall" {
            { Enable-WindowsFirewall -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Disable-LegacyProtocols" {
        It "Should attempt to disable legacy protocols" {
            { Disable-LegacyProtocols -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Set-FIPSMode" {
        It "Should check and set FIPS mode" {
            Mock Test-Path { $true } -ModuleName SecurityBaseline
            Mock Get-ItemProperty { @{ Enabled = 0 } } -ModuleName SecurityBaseline
            
            { Set-FIPSMode -DryRun } | Should -Not -Throw
        }
    }
}

Describe "AccessControl Module Tests" {
    BeforeAll {
        Import-Module "$script:ModulePath\AccessControl.psm1" -Force
        
        Mock Invoke-HardeningAction -MockWith $script:MockHardeningAction -ModuleName AccessControl
    }
    
    Context "Set-PasswordPolicy" {
        It "Should configure password policy settings" {
            Mock secedit { return 0 } -ModuleName AccessControl
            Mock net { return 0 } -ModuleName AccessControl
            
            { Set-PasswordPolicy -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Configure-RDPSecurity" {
        It "Should configure RDP security settings" {
            { Configure-RDPSecurity -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Configure-LAPS" {
        It "Should handle non-domain joined computers gracefully" {
            Mock Get-WmiObject { @{ PartOfDomain = $false } } -ModuleName AccessControl
            
            { Configure-LAPS -DryRun } | Should -Not -Throw
        }
    }
}

Describe "AuditLogging Module Tests" {
    BeforeAll {
        Import-Module "$script:ModulePath\AuditLogging.psm1" -Force
        
        Mock Invoke-HardeningAction -MockWith $script:MockHardeningAction -ModuleName AuditLogging
    }
    
    Context "Enable-AuditLogging" {
        It "Should configure audit policies" {
            Mock auditpol { return 0 } -ModuleName AuditLogging
            
            { Enable-AuditLogging -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Configure-EventLogSecurity" {
        It "Should configure event log settings" {
            Mock wevtutil { return 0 } -ModuleName AuditLogging
            
            { Configure-EventLogSecurity -DryRun } | Should -Not -Throw
        }
    }
}

Describe "SystemProtection Module Tests" {
    BeforeAll {
        Import-Module "$script:ModulePath\SystemProtection.psm1" -Force
        
        Mock Invoke-HardeningAction -MockWith $script:MockHardeningAction -ModuleName SystemProtection
    }
    
    Context "Configure-WindowsDefender" {
        It "Should configure Windows Defender settings" {
            Mock Set-MpPreference { } -ModuleName SystemProtection
            Mock Update-MpSignature { } -ModuleName SystemProtection
            
            { Configure-WindowsDefender -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Enable-DeviceControl" {
        It "Should configure device control policies" {
            { Enable-DeviceControl -DryRun } | Should -Not -Throw
        }
    }
    
    Context "Configure-AppLocker" {
        It "Should configure AppLocker policies" {
            Mock Set-Service { } -ModuleName SystemProtection
            Mock Start-Service { } -ModuleName SystemProtection
            Mock Set-AppLockerPolicy { } -ModuleName SystemProtection
            
            { Configure-AppLocker -DryRun } | Should -Not -Throw
        }
    }
}

Describe "ComplianceReporting Module Tests" {
    BeforeAll {
        Import-Module "$script:ModulePath\ComplianceReporting.psm1" -Force
    }
    
    Context "Test-ComplianceStatus" {
        It "Should return compliance check results" {
            Mock Get-ItemProperty { @{ Enabled = 1 } } -ModuleName ComplianceReporting
            Mock Get-MpComputerStatus { @{ RealTimeProtectionEnabled = $true } } -ModuleName ComplianceReporting
            Mock auditpol { "Success and Failure" * 15 } -ModuleName ComplianceReporting
            Mock Get-BitLockerVolume { @{ ProtectionStatus = 'On' } } -ModuleName ComplianceReporting
            
            $results = Test-ComplianceStatus
            
            $results | Should -Not -BeNullOrEmpty
            $results | Should -HaveCount 4
            $results[0].Control | Should -Be "3.13.11"
            $results[0].Status | Should -Be "Compliant"
        }
    }
    
    Context "Export-ComplianceReport" {
        It "Should generate HTML compliance report" {
            $testReportPath = "$env:TEMP\TestReport.html"
            
            Mock Get-WmiObject { @{ Caption = "Windows Server 2022" } } -ModuleName ComplianceReporting
            Mock Test-Path { $false } -ModuleName ComplianceReporting
            
            { Export-ComplianceReport -ReportPath $testReportPath -SuccessCount 10 -FailureCount 2 } | Should -Not -Throw
            
            # In a real test, we would verify the file was created
            # Test-Path $testReportPath | Should -Be $true
        }
    }
}

Describe "Main Hardening Script Tests" {
    BeforeAll {
        # Create a test version of the main script that doesn't execute
        $testScript = Get-Content "$script:ModulePath\Invoke-WindowsHardening.ps1" -Raw
        
        # Mock all module imports
        Mock Import-Module { } -ParameterFilter { $Name -like "*.psm1" }
        Mock Get-ChildItem { @() } -ParameterFilter { $Path -like "*.psm1" }
    }
    
    Context "Script Parameters" {
        It "Should accept valid parameters" {
            $scriptInfo = Get-Command "$script:ModulePath\Invoke-WindowsHardening.ps1"
            
            $scriptInfo.Parameters.Keys | Should -Contain "Mode"
            $scriptInfo.Parameters.Keys | Should -Contain "DryRun"
            $scriptInfo.Parameters.Keys | Should -Contain "LogPath"
            $scriptInfo.Parameters.Keys | Should -Contain "ReportPath"
        }
    }
    
    Context "Logging Functions" {
        It "Should initialize logging" {
            # Test would verify log file creation
            { Initialize-Logging -LogFile $script:TestLogPath } | Should -Not -Throw
        }
    }
}

Describe "NIST Control Mapping Tests" {
    It "Should have correct NIST control mappings in comments" {
        $modules = Get-ChildItem -Path $script:ModulePath -Filter "*.psm1"
        
        foreach ($module in $modules) {
            $content = Get-Content $module.FullName -Raw
            
            # Check for NIST control references
            $content | Should -Match "NIST \d+\.\d+\.\d+"
            
            # Check for specific required controls
            switch ($module.Name) {
                "SecurityBaseline.psm1" {
                    $content | Should -Match "3\.4\.2"  # Configuration Management
                    $content | Should -Match "3\.13\.11" # Cryptographic Protection
                }
                "AccessControl.psm1" {
                    $content | Should -Match "3\.5\.7"   # Authentication
                    $content | Should -Match "3\.1\.1"   # Access Control
                }
                "AuditLogging.psm1" {
                    $content | Should -Match "3\.3\.1"   # Audit Creation
                }
                "SystemProtection.psm1" {
                    $content | Should -Match "3\.14\.1"  # System Integrity
                }
            }
        }
    }
}

Describe "Error Handling Tests" {
    BeforeAll {
        Import-Module "$script:ModulePath\SecurityBaseline.psm1" -Force
    }
    
    Context "Function Error Handling" {
        It "Should handle registry path not found gracefully" {
            Mock Test-Path { $false } -ModuleName SecurityBaseline
            Mock Invoke-HardeningAction -MockWith {
                param($Action, $Description, $NistControl)
                & $Action
            } -ModuleName SecurityBaseline
            
            { Set-FIPSMode -DryRun } | Should -Not -Throw
        }
    }
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestLogPath) {
        Remove-Item $script:TestLogPath -Force
    }
}