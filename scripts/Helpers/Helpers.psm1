[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'Want to just write to the console, not the pipeline.'
)]
param()

function Convert-VersionSpec {
    <#
            .SYNOPSIS
            Converts legacy version parameters into a NuGet version range string.

            .DESCRIPTION
            This function takes minimum, maximum, or required version parameters
            and constructs a NuGet-compatible version range string.

            - If `RequiredVersion` is specified, the output is an exact match range.
            - If both `MinimumVersion` and `MaximumVersion` are provided,
              an inclusive range is returned.
            - If only `MinimumVersion` is provided, it returns a minimum-inclusive range.
            - If only `MaximumVersion` is provided, it returns an upper-bound range.
            - If no parameters are provided, `$null` is returned.

            .EXAMPLE
            Convert-VersionSpec -MinimumVersion "1.0.0" -MaximumVersion "2.0.0"

            Output:
            ```powershell
            [1.0.0,2.0.0]
            ```

            Returns an inclusive version range from 1.0.0 to 2.0.0.

            .EXAMPLE
            Convert-VersionSpec -RequiredVersion "1.5.0"

            Output:
            ```powershell
            [1.5.0]
            ```

            Returns an exact match for version 1.5.0.

            .EXAMPLE
            Convert-VersionSpec -MinimumVersion "1.0.0"

            Output:
            ```powershell
            [1.0.0, ]
            ```

            Returns a minimum-inclusive version range starting at 1.0.0.

            .EXAMPLE
            Convert-VersionSpec -MaximumVersion "2.0.0"

            Output:
            ```powershell
            (, 2.0.0]
            ```

            Returns an upper-bound range up to version 2.0.0.

            .OUTPUTS
            string

            .NOTES
            The NuGet version range string based on the provided parameters.
            The returned string follows NuGet versioning syntax.

            .LINK
            https://psmodule.io/Convert/Functions/Convert-VersionSpec
        #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        # The minimum version for the range. If specified alone, the range is open-ended upwards.
        [Parameter()]
        [string] $MinimumVersion,

        # The maximum version for the range. If specified alone, the range is open-ended downwards.
        [Parameter()]
        [string] $MaximumVersion,

        # Specifies an exact required version. If set, an exact version range is returned.
        [Parameter()]
        [string] $RequiredVersion
    )

    if ($RequiredVersion) {
        # Use exact match in bracket notation.
        return "[$RequiredVersion]"
    } elseif ($MinimumVersion -and $MaximumVersion) {
        # Both bounds provided; both are inclusive.
        return "[$MinimumVersion,$MaximumVersion]"
    } elseif ($MinimumVersion) {
        # Only a minimum is provided. Use a minimum-inclusive range.
        return "[$MinimumVersion, ]"
    } elseif ($MaximumVersion) {
        # Only a maximum is provided; lower bound open.
        return "(, $MaximumVersion]"
    } else {
        return $null
    }
}

function Import-PSModule {
    <#
    .SYNOPSIS
    Imports a build PS module.

    .DESCRIPTION
    Imports a build PS module.

    .EXAMPLE
    Import-PSModule -SourceFolderPath $ModuleFolderPath -ModuleName $moduleName

    Imports a module located at $ModuleFolderPath with the name $moduleName.
    #>
    [CmdletBinding()]
    param(
        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [string] $Path
    )

    $moduleName = Split-Path -Path $Path -Leaf
    $manifestFilePath = Join-Path -Path $Path "$moduleName.psd1"

    Write-Host " - Manifest file path: [$manifestFilePath]"
    Resolve-PSModuleDependency -ManifestFilePath $manifestFilePath

    Write-Host ' - List installed modules'
    Get-InstalledPSResource | Format-Table -AutoSize | Out-String

    Write-Host " - Importing module [$moduleName] v999"
    Import-Module $Path

    Write-Host ' - List loaded modules'
    $availableModules = Get-Module -ListAvailable -Refresh -Verbose:$false
    $availableModules | Select-Object Name, Version, Path | Sort-Object Name | Format-Table -AutoSize | Out-String
    Write-Host ' - List commands'
    $commands = Get-Command -Module $moduleName -ListImported
    Get-Command -Module $moduleName -ListImported | Format-Table -AutoSize | Out-String

    if ($moduleName -notin $commands.Source) {
        throw 'Module not found'
    }
}

function Resolve-PSModuleDependency {
    <#
        .SYNOPSIS
        Resolves module dependencies from a manifest file using Install-PSResource.

        .DESCRIPTION
        Reads a module manifest (PSD1) and for each required module converts the old
        Install-Module parameters (MinimumVersion, MaximumVersion, RequiredVersion)
        into a single NuGet version range string for Install-PSResource's –Version parameter.
        (Note: If RequiredVersion is set, that value takes precedence.)

        .EXAMPLE
        Resolve-PSModuleDependency -ManifestFilePath 'C:\MyModule\MyModule.psd1'
        Installs all modules defined in the manifest file, following PSModuleInfo structure.

        .NOTES
        Should later be adapted to support both pre-reqs, and dependencies.
        Should later be adapted to take 4 parameters sets: specific version ("requiredVersion" | "GUID"), latest version ModuleVersion,
        and latest version within a range MinimumVersion - MaximumVersion.
    #>
    [CmdletBinding()]
    param(
        # The path to the manifest file.
        [Parameter(Mandatory)]
        [string] $ManifestFilePath
    )

    Write-Host 'Resolving dependencies'
    $manifest = Import-PowerShellDataFile -Path $ManifestFilePath
    Write-Host " - Reading [$ManifestFilePath]"
    Write-Host " - Found [$($manifest.RequiredModules.Count)] module(s) to install"

    foreach ($requiredModule in $manifest.RequiredModules) {
        # Build parameters for Install-PSResource (new version spec).
        $psResourceParams = @{
            TrustRepository = $true
        }
        # Build parameters for Import-Module (legacy version spec).
        $importParams = @{
            Force   = $true
            Verbose = $false
        }

        if ($requiredModule -is [string]) {
            $psResourceParams.Name = $requiredModule
            $importParams.Name = $requiredModule
        } else {
            $psResourceParams.Name = $requiredModule.ModuleName
            $importParams.Name = $requiredModule.ModuleName

            # Convert legacy version info for Install-PSResource.
            $versionSpec = Convert-VersionSpec `
                -MinimumVersion $requiredModule.ModuleVersion `
                -MaximumVersion $requiredModule.MaximumVersion `
                -RequiredVersion $requiredModule.RequiredVersion

            if ($versionSpec) {
                $psResourceParams.Version = $versionSpec
            }

            # For Import-Module, keep the original version parameters.
            if ($requiredModule.ModuleVersion) {
                $importParams.MinimumVersion = $requiredModule.ModuleVersion
            }
            if ($requiredModule.RequiredVersion) {
                $importParams.RequiredVersion = $requiredModule.RequiredVersion
            }
            if ($requiredModule.MaximumVersion) {
                $importParams.MaximumVersion = $requiredModule.MaximumVersion
            }
        }

        Write-Host " - [$($psResourceParams.Name)] - Installing module with Install-PSResource using version spec: $($psResourceParams.Version)"
        $VerbosePreferenceOriginal = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $retryCount = 5
        $retryDelay = 10
        for ($i = 0; $i -lt $retryCount; $i++) {
            try {
                Install-PSResource @psResourceParams
                break
            } catch {
                Write-Warning "Installation of $($psResourceParams.Name) failed with error: $_"
                if ($i -eq $retryCount - 1) {
                    throw
                }
                Write-Warning "Retrying in $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
            }
        }
        $VerbosePreference = $VerbosePreferenceOriginal

        Write-Host " - [$($importParams.Name)] - Importing module with legacy version spec"
        $VerbosePreferenceOriginal = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        Import-Module @importParams
        $VerbosePreference = $VerbosePreferenceOriginal
        Write-Host " - [$($importParams.Name)] - Done"
    }
    Write-Host ' - Resolving dependencies - Done'
}

function Show-FileContent {
    <#
        .SYNOPSIS
        Prints the content of a file with line numbers in front of each line.

        .DESCRIPTION
        Prints the content of a file with line numbers in front of each line.

        .EXAMPLE
        $Path = 'C:\Utilities\Show-FileContent.ps1'
        Show-FileContent -Path $Path

        Shows the content of the file with line numbers in front of each line.
    #>
    [CmdletBinding()]
    param (
        # The path to the file to show the content of.
        [Parameter(Mandatory)]
        [string] $Path
    )

    $content = Get-Content -Path $Path
    $lineNumber = 1
    $columnSize = $content.Count.ToString().Length
    # Foreach line print the line number in front of the line with [    ] around it.
    # The linenumber should dynamically adjust to the number of digits with the length of the file.
    foreach ($line in $content) {
        $lineNumberFormatted = $lineNumber.ToString().PadLeft($columnSize)
        Write-Host "[$lineNumberFormatted] $line"
        $lineNumber++
    }
}

function Install-PSModule {
    <#
        .SYNOPSIS
        Installs a build PS module.

        .DESCRIPTION
        Installs a build PS module.

        .EXAMPLE
        Install-PSModule -SourceFolderPath $ModuleFolderPath -ModuleName $moduleName

        Installs a module located at $ModuleFolderPath with the name $moduleName.
    #>
    [CmdletBinding()]
    param(
        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [string] $Path,

        # Return the path of the installed module
        [Parameter()]
        [switch] $PassThru
    )

    $moduleName = Split-Path -Path $Path -Leaf
    $manifestFilePath = Join-Path -Path $Path "$moduleName.psd1"
    Write-Verbose " - Manifest file path: [$manifestFilePath]" -Verbose
    Write-Host '::group::Resolving dependencies'
    Resolve-PSModuleDependency -ManifestFilePath $manifestFilePath
    Write-Host '::endgroup::'
    $PSModulePath = $env:PSModulePath -split [System.IO.Path]::PathSeparator | Select-Object -First 1
    $codePath = New-Item -Path "$PSModulePath/$moduleName/999.0.0" -ItemType Directory -Force | Select-Object -ExpandProperty FullName
    Copy-Item -Path "$Path/*" -Destination $codePath -Recurse -Force
    Write-Host '::group::Importing module'
    Import-Module -Name $moduleName -Verbose
    Write-Host '::endgroup::'
    if ($PassThru) {
        return $codePath
    }
}

function Get-ModuleManifest {
    <#
        .SYNOPSIS
        Get the module manifest.

        .DESCRIPTION
        Get the module manifest as a path, file info, content, or hashtable.

        .EXAMPLE
        Get-PSModuleManifest -Path 'src/PSModule/PSModule.psd1' -As Hashtable
    #>
    [OutputType([string], [System.IO.FileInfo], [System.Collections.Hashtable], [System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param(
        # Path to the module manifest file.
        [Parameter(Mandatory)]
        [string] $Path,

        # The format of the output.
        [Parameter()]
        [ValidateSet('FileInfo', 'Content', 'Hashtable')]
        [string] $As = 'Hashtable'
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Warning 'No manifest file found.'
        return $null
    }
    Write-Verbose "Found manifest file [$Path]"

    switch ($As) {
        'FileInfo' {
            return Get-Item -Path $Path
        }
        'Content' {
            return Get-Content -Path $Path
        }
        'Hashtable' {
            $manifest = [System.Collections.Specialized.OrderedDictionary]@{}
            $psData = [System.Collections.Specialized.OrderedDictionary]@{}
            $privateData = [System.Collections.Specialized.OrderedDictionary]@{}
            $tempManifest = Import-PowerShellDataFile -Path $Path
            if ($tempManifest.ContainsKey('PrivateData')) {
                $tempPrivateData = $tempManifest.PrivateData
                if ($tempPrivateData.ContainsKey('PSData')) {
                    $tempPSData = $tempPrivateData.PSData
                    $tempPrivateData.Remove('PSData')
                }
            }

            $psdataOrder = @(
                'Tags'
                'LicenseUri'
                'ProjectUri'
                'IconUri'
                'ReleaseNotes'
                'Prerelease'
                'RequireLicenseAcceptance'
                'ExternalModuleDependencies'
            )
            foreach ($key in $psdataOrder) {
                if (($null -ne $tempPSData) -and ($tempPSData.ContainsKey($key))) {
                    $psData.$key = $tempPSData.$key
                }
            }
            if ($psData.Count -gt 0) {
                $privateData.PSData = $psData
            } else {
                $privateData.Remove('PSData')
            }
            foreach ($key in $tempPrivateData.Keys) {
                $privateData.$key = $tempPrivateData.$key
            }

            $manifestOrder = @(
                'RootModule'
                'ModuleVersion'
                'CompatiblePSEditions'
                'GUID'
                'Author'
                'CompanyName'
                'Copyright'
                'Description'
                'PowerShellVersion'
                'PowerShellHostName'
                'PowerShellHostVersion'
                'DotNetFrameworkVersion'
                'ClrVersion'
                'ProcessorArchitecture'
                'RequiredModules'
                'RequiredAssemblies'
                'ScriptsToProcess'
                'TypesToProcess'
                'FormatsToProcess'
                'NestedModules'
                'FunctionsToExport'
                'CmdletsToExport'
                'VariablesToExport'
                'AliasesToExport'
                'DscResourcesToExport'
                'ModuleList'
                'FileList'
                'HelpInfoURI'
                'DefaultCommandPrefix'
                'PrivateData'
            )
            foreach ($key in $manifestOrder) {
                if ($tempManifest.ContainsKey($key)) {
                    $manifest.$key = $tempManifest.$key
                }
            }
            if ($privateData.Count -gt 0) {
                $manifest.PrivateData = $privateData
            } else {
                $manifest.Remove('PrivateData')
            }

            return $manifest
        }
    }
}
