$script:dscModuleName   = 'WebAdministrationDsc'
$script:dscResourceName = 'DSC_WebVirtualDirectory'

try
{
    Import-Module -Name DscResource.Test -Force -ErrorAction 'Stop'
}
catch [System.IO.FileNotFoundException]
{
    throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
}

$script:testEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $script:dscModuleName `
    -DSCResourceName $script:dscResourceName `
    -ResourceType 'Mof' `
    -TestType 'Integration'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelper\CommonTestHelper.psm1') -Force

$tempName = "$($script:dscResourceName)_" + (Get-Date).ToString('yyyyMMdd_HHmmss')

try
{
    $null = Backup-WebConfiguration -Name $tempName

    # Now that WebAdministrationDsc should be discoverable load the configuration data
    $ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:dscResourceName).config.ps1"
    . $ConfigFile

    $dscConfig = Import-LocalizedData -BaseDirectory $PSScriptRoot -FileName "$($script:dscResourceName).config.psd1"

    Describe "$($script:dscResourceName)_Initialize" {
        Invoke-Expression -Command "$($script:dscResourceName)_Initialize -ConfigurationData `$DSCConfig -OutputPath `$TestDrive"
        Start-DscConfiguration -Path $TestDrive -ComputerName localhost -Wait -Verbose -Force
    }

    Describe "$($script:dscResourceName)_Present" {
        #region DEFAULT TESTS
        It 'Should compile the MOF without throwing' {
            {
                & "$($script:DSCResourceName)_Present" `
                    -OutputPath $TestDrive `
                    -ConfigurationData $dscConfig `
            } | Should -Not -Throw
        }

        It 'Should apply the MOF without throwing' {
            {
                Reset-DscLcm

                Start-DscConfiguration `
                    -Path $TestDrive `
                    -ComputerName localhost `
                    -Wait `
                    -Verbose `
                    -Force `
                    -ErrorAction Stop
            } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }
        #endregion

        It 'Should create a WebVirtualDirectory with correct settings' -Test {
            & "$($script:DSCResourceName)_Present" `
            -OutputPath $TestDrive `
            -ConfigurationData $dscConfig

        Reset-DscLcm

        Start-DscConfiguration `
            -Path $TestDrive `
            -ComputerName localhost `
            -Wait `
            -Verbose `
            -Force `
            -ErrorAction Stop

            # Build results to test
            $result = Get-WebVirtualDirectory -Site $DSCConfig.AllNodes.Website `
                -Application $DSCConfig.AllNodes.WebApplication `
                -Name $DSCConfig.AllNodes.WebVirtualDirectory

            # Test virtual directory settings are correct
            $result.path            | Should Be "/$($DSCConfig.AllNodes.WebVirtualDirectory)"
            $result.physicalPath    | Should Be $DSCConfig.AllNodes.PhysicalPath
        }

        It 'Should create a WebVirtualDirectory with WebApplication = ''/''' -Test {

            configuration DSC_WebVirtualDirectory_WebApplicationSlash
            {
                Import-DscResource -ModuleName WebAdministrationDsc

                Node $AllNodes.NodeName
                {
                    WebVirtualDirectory WebVirtualDirectory
                    {
                        Ensure = 'Present'
                        Website = $Node.Website
                        WebApplication = '/'
                        Name = $Node.WebVirtualDirectory
                        PhysicalPath = $Node.PhysicalPath
                    }
                }
            }

            & "DSC_WebVirtualDirectory_WebApplicationSlash" `
            -OutputPath $TestDrive `
            -ConfigurationData $dscConfig

            Reset-DscLcm

            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            # Build results to test
            $result = Get-WebVirtualDirectory -Site $DSCConfig.AllNodes.Website `
                -Application '/' `
                -Name $DSCConfig.AllNodes.WebVirtualDirectory

            # Test virtual directory settings are correct
            $result                 | Should Not BeNullOrEmpty
        }
    }

    Describe "$($script:dscResourceName)_Absent" {
        #region DEFAULT TESTS
        It 'Should compile the MOF without throwing' {
            {
                & "$($script:DSCResourceName)_Absent" `
                    -OutputPath $TestDrive `
                    -ConfigurationData $dscConfig
            } | Should -Not -Throw
        }

        It 'Should apply the MOF without throwing' {
            {
                Reset-DscLcm

                Start-DscConfiguration `
                    -Path $TestDrive `
                    -ComputerName localhost `
                    -Wait `
                    -Verbose `
                    -Force `
                    -ErrorAction Stop
            } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }
        #endregion

        It 'Should remove the WebVirtualDirectory' -Test {
            & "$($script:DSCResourceName)_Absent" `
                    -OutputPath $TestDrive `
                    -ConfigurationData $dscConfig

            Reset-DscLcm

            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            # Build results to test
            $result = Get-WebVirtualDirectory -Site $DSCConfig.AllNodes.Website `
                -Application $DSCConfig.AllNodes.WebApplication `
                -Name $DSCConfig.AllNodes.WebVirtualDirectory

            # Test virtual directory is removed
            $result | Should BeNullOrEmpty
        }

        It 'Should remove a WebVirtualDirectory with WebApplication = ''''' -Test {
            # Avoid collision with other tests
            $virtualDirectoryName = "$($Node.WebVirtualDirectory)2"

            # Declare local configurations
            configuration DSC_WebVirtualDirectory_WebApplicationBlank_add
            {
                Import-DscResource -ModuleName WebAdministrationDsc

                Node $AllNodes.NodeName
                {
                    WebVirtualDirectory WebVirtualDirectory
                    {
                        Ensure = 'Present'
                        Website = $Node.Website
                        WebApplication = ''
                        Name = $virtualDirectoryName
                        PhysicalPath = $Node.PhysicalPath
                    }
                }
            }

            configuration DSC_WebVirtualDirectory_WebApplicationBlank_remove
            {
                Import-DscResource -ModuleName WebAdministrationDsc

                Node $AllNodes.NodeName
                {
                    WebVirtualDirectory WebVirtualDirectory
                    {
                        Ensure = 'Absent'
                        Website = $Node.Website
                        WebApplication = ''
                        Name = $virtualDirectoryName
                        PhysicalPath = $Node.PhysicalPath
                    }
                }
            }

            # local helper
            function Get-WebApplicationBlankVirtualDirectory()
            {
                return Get-WebVirtualDirectory -Site $DSCConfig.AllNodes.Website `
                    -Application '' `
                    -Name $virtualDirectoryName
            }

            # Execute setup
            & "DSC_WebVirtualDirectory_WebApplicationBlank_add" `
            -OutputPath $TestDrive `
            -ConfigurationData $dscConfig

            Reset-DscLcm

            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            # Verify intermediate result
            $resultIntermediate = Get-WebApplicationBlankVirtualDirectory

            # Virtual directory have been created
            $resultIntermediate     | Should Not BeNullOrEmpty

            # Execute Test operation
            & "DSC_WebVirtualDirectory_WebApplicationBlank_remove" `
            -OutputPath $TestDrive `
            -ConfigurationData $dscConfig

            <#
                Issue #366
                Before change this statement throws exception
                "PowerShell Desired State Configuration does not support execution of commands in an interactive mode ..."
            #>
            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            # Build results to test
            $result = Get-WebApplicationBlankVirtualDirectory

            # Test virtual directory is removed
            $result | Should BeNullOrEmpty
        }
    }

    Describe "$($script:dscResourceName)_CreateUpdateRemove_WebApplicationAndName" {

        function Invoke-CreateUpdateRemove()
        {
            [CmdletBinding()]
            param
            (
                [Parameter()]
                $webApplication,
                [Parameter()]
                $name
            )

            configuration DSC_WebVirtualDirectory_Present
            {
                Import-DscResource -ModuleName WebAdministrationDsc

                Node $AllNodes.NodeName
                {
                    WebVirtualDirectory WebVirtualDirectory
                    {
                        Ensure = 'Present'
                        Website = $Node.Website
                        WebApplication = $webApplication
                        Name = $name
                        PhysicalPath = $Node.PhysicalPath
                    }
                }
            }

            configuration DSC_WebVirtualDirectory_Absent
            {
                Import-DscResource -ModuleName WebAdministrationDsc

                Node $AllNodes.NodeName
                {
                    WebVirtualDirectory WebVirtualDirectory
                    {
                        Ensure = 'Absent'
                        Website = $Node.Website
                        WebApplication = $webApplication
                        Name = $name
                        PhysicalPath = $Node.PhysicalPath
                    }
                }
            }

            function Get-VirtualDirectoryShortcut()
            {
                $got = Get-WebVirtualDirectory `
                    -Site $DSCConfig.AllNodes.Website `
                    -Application $webApplication `
                    -Name $name
                return $got
            }

            DSC_WebVirtualDirectory_Present `
            -OutputPath $TestDrive `
            -ConfigurationData $dscConfig

            Reset-DscLcm

            # 1. Add
            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            $result = Get-VirtualDirectoryShortcut
            $result | Should Not BeNullOrEmpty

            # 2. Update
            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            $result = Get-VirtualDirectoryShortcut
            $result | Should Not BeNullOrEmpty

            # 3. Remove
            DSC_WebVirtualDirectory_Absent `
            -OutputPath $TestDrive `
            -ConfigurationData $dscConfig

            Start-DscConfiguration `
                -Path $TestDrive `
                -ComputerName localhost `
                -Wait `
                -Verbose `
                -Force `
                -ErrorAction Stop

            $result = Get-VirtualDirectoryShortcut
            $result | Should BeNullOrEmpty
        }

        It 'Should work with application blank single name' -Test {
            Invoke-CreateUpdateRemove '' 't1'
        }

        It 'Should work with application blank two name' -Test {
            Invoke-CreateUpdateRemove '' 't2/t3'
        }

        It 'Should work with application blank three name' -Test {
            Invoke-CreateUpdateRemove '' 't3/t4/t5'
        }

        It 'Should work with application exist one name' -Test {
            Invoke-CreateUpdateRemove $DSCConfig.AllNodes.WebApplication 't4'
        }

        It 'Should work with application exist two name' -Test {
            Invoke-CreateUpdateRemove $DSCConfig.AllNodes.WebApplication 't5/t6'
        }

        It 'Should work with application exist three name' -Test {
            Invoke-CreateUpdateRemove $DSCConfig.AllNodes.WebApplication 't6/t7/t8'
        }

        It 'Should fail with application fake one name' -Test {
            { Invoke-CreateUpdateRemove 'DummyApp' 't7' } | Should -Throw
        }

        It 'Should fail with application fake two name' -Test {
            { Invoke-CreateUpdateRemove 'DummyApp' 't8/t9' } | Should -Throw
        }
    }
}
finally
{
    Restore-WebConfigurationWrapper -Name $tempName -Verbose

    Remove-WebConfigurationBackup -Name $tempName -Verbose

    if ((Test-Path -Path $DSCConfig.AllNodes.PhysicalPath)) {
        Remove-Item -Path $DSCConfig.AllNodes.PhysicalPath
    }

    if ((Test-Path -Path $DSCConfig.AllNodes.WebApplicationPhysicalPath)) {
        Remove-Item -Path $DSCConfig.AllNodes.WebApplicationPhysicalPath
    }

    Restore-TestEnvironment -TestEnvironment $script:testEnvironment -Verbose
}
