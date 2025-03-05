[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'LogGroup - Scoping affects the variables line of sight.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'Want to just write to the console, not the pipeline.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidLongLines', '',
    Justification = 'Easier to read the multi ternery operators in a single line.'
)]
param()

function Add-ContentFromItem {
    <#
        .SYNOPSIS
        Add the content of a folder or file to the root module file.

        .DESCRIPTION
        This function will add the content of a folder or file to the root module file.

        .EXAMPLE
        Add-ContentFromItem -Path 'C:\MyModule\src\MyModule' -RootModuleFilePath 'C:\MyModule\src\MyModule.psm1' -RootPath 'C:\MyModule\src'
    #>
    param(
        # The path to the folder or file to process.
        [Parameter(Mandatory)]
        [string] $Path,

        # The path to the root module file.
        [Parameter(Mandatory)]
        [string] $RootModuleFilePath,

        # The root path of the module.
        [Parameter(Mandatory)]
        [string] $RootPath
    )
    # Get the path separator for the current OS
    $pathSeparator = [System.IO.Path]::DirectorySeparatorChar

    $relativeFolderPath = $Path -Replace $RootPath, ''
    $relativeFolderPath = $relativeFolderPath -Replace $file.Extension, ''
    $relativeFolderPath = $relativeFolderPath.TrimStart($pathSeparator)
    $relativeFolderPath = $relativeFolderPath -Split $pathSeparator | ForEach-Object { "[$_]" }
    $relativeFolderPath = $relativeFolderPath -Join ' - '

    Add-Content -Path $RootModuleFilePath -Force -Value @"
#region    $relativeFolderPath
Write-Debug "[`$scriptName] - $relativeFolderPath - Processing folder"
"@

    $files = $Path | Get-ChildItem -File -Force -Filter '*.ps1' | Sort-Object -Property FullName
    foreach ($file in $files) {
        $relativeFilePath = $file.FullName -Replace $RootPath, ''
        $relativeFilePath = $relativeFilePath -Replace $file.Extension, ''
        $relativeFilePath = $relativeFilePath.TrimStart($pathSeparator)
        $relativeFilePath = $relativeFilePath -Split $pathSeparator | ForEach-Object { "[$_]" }
        $relativeFilePath = $relativeFilePath -Join ' - '

        Add-Content -Path $RootModuleFilePath -Force -Value @"
#region    $relativeFilePath
Write-Debug "[`$scriptName] - $relativeFilePath - Importing"
"@
        Get-Content -Path $file.FullName | Add-Content -Path $RootModuleFilePath -Force
        Add-Content -Path $RootModuleFilePath -Value @"
Write-Debug "[`$scriptName] - $relativeFilePath - Done"
#endregion $relativeFilePath
"@
    }

    $subFolders = $Path | Get-ChildItem -Directory -Force | Sort-Object -Property Name
    foreach ($subFolder in $subFolders) {
        Add-ContentFromItem -Path $subFolder.FullName -RootModuleFilePath $RootModuleFilePath -RootPath $RootPath
    }
    Add-Content -Path $RootModuleFilePath -Force -Value @"
Write-Debug "[`$scriptName] - $relativeFolderPath - Done"
#endregion $relativeFolderPath
"@
}

function Build-PSModule {
    <#
        .SYNOPSIS
        Builds a module.

        .DESCRIPTION
        Builds a module.
    #>
    [OutputType([void])]
    [CmdletBinding()]
    param(
        # Name of the module.
        [Parameter(Mandatory)]
        [string] $ModuleName,

        # Path to the folder where the modules are located.
        [Parameter(Mandatory)]
        [string] $ModuleSourceFolderPath,

        # Path to the folder where the built modules are outputted.
        [Parameter(Mandatory)]
        [string] $ModuleOutputFolderPath
    )

    LogGroup "Building module [$ModuleName]" {
        $moduleSourceFolder = Get-Item -Path $ModuleSourceFolderPath
        $moduleOutputFolder = New-Item -Path $ModuleOutputFolderPath -Name $ModuleName -ItemType Directory -Force
        [pscustomobject]@{
            ModuleSourceFolderPath = $moduleSourceFolder
            ModuleOutputFolderPath = $moduleOutputFolder
        } | Format-List | Out-String
    }

    Build-PSModuleBase -ModuleName $ModuleName -ModuleSourceFolder $moduleSourceFolder -ModuleOutputFolder $moduleOutputFolder
    Build-PSModuleManifest -ModuleName $ModuleName -ModuleOutputFolder $moduleOutputFolder
    Build-PSModuleRootModule -ModuleName $ModuleName -ModuleOutputFolder $moduleOutputFolder
    Update-PSModuleManifestAliasesToExport -ModuleName $ModuleName -ModuleOutputFolder $moduleOutputFolder

    LogGroup 'Build manifest file - Final Result' {
        $outputManifestPath = Join-Path -Path $ModuleOutputFolder -ChildPath "$ModuleName.psd1"
        Show-FileContent -Path $outputManifestPath
    }
}

function Build-PSModuleBase {
    <#
    .SYNOPSIS
    Compiles the base module files.

    .DESCRIPTION
    This function will compile the base module files.
    It will copy the source files to the output folder and remove the files that are not needed.

    .EXAMPLE
    Build-PSModuleBase -SourceFolderPath 'C:\MyModule\src\MyModule' -OutputFolderPath 'C:\MyModule\build\MyModule'
    #>
    [CmdletBinding()]
    param(
        # Name of the module.
        [Parameter(Mandatory)]
        [string] $ModuleName,

        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo] $ModuleSourceFolder,

        # Path to the folder where the built modules are outputted.
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo] $ModuleOutputFolder
    )

    LogGroup 'Build base' {
        $relModuleSourceFolder = $ModuleSourceFolder | Resolve-Path -Relative
        $relModuleOutputFolder = $ModuleOutputFolder | Resolve-Path -Relative
        Write-Host "Copying files from [$relModuleSourceFolder] to [$relModuleOutputFolder]"
        Copy-Item -Path "$ModuleSourceFolder\*" -Destination $ModuleOutputFolder -Recurse -Force -Exclude "$ModuleName.psm1"
        $null = New-Item -Path $ModuleOutputFolder -Name "$ModuleName.psm1" -ItemType File -Force
    }

    LogGroup 'Build base - Result' {
        Get-ChildItem -Path $ModuleOutputFolder -Recurse -Force | Resolve-Path -Relative | Sort-Object
    }
}

function Build-PSModuleDocumentation {
    <#
    .SYNOPSIS
    Builds a module.

    .DESCRIPTION
    Builds a module.
    #>
    [CmdletBinding()]
    param(
        # Name of the module.
        [Parameter(Mandatory)]
        [string] $ModuleName,

        # Path to the folder where the modules are located.
        [Parameter(Mandatory)]
        [string] $ModuleSourceFolderPath,

        # Path to the folder where the built modules are outputted.
        [Parameter(Mandatory)]
        [string] $ModulesOutputFolderPath,

        # Path to the folder where the documentation is outputted.
        [Parameter(Mandatory)]
        [string] $DocsOutputFolderPath
    )

    Write-Host "::group::Documenting module [$ModuleName]"
    [pscustomobject]@{
        ModuleName              = $ModuleName
        ModuleSourceFolderPath  = $ModuleSourceFolderPath
        ModulesOutputFolderPath = $ModulesOutputFolderPath
        DocsOutputFolderPath    = $DocsOutputFolderPath
    } | Format-List | Out-String

    if (-not (Test-Path -Path $ModuleSourceFolderPath)) {
        Write-Error "Source folder not found at [$ModuleSourceFolderPath]"
        exit 1
    }
    $moduleSourceFolder = Get-Item -Path $ModuleSourceFolderPath
    $moduleOutputFolder = New-Item -Path $ModulesOutputFolderPath -Name $ModuleName -ItemType Directory -Force
    $docsOutputFolder = New-Item -Path $DocsOutputFolderPath -ItemType Directory -Force

    Write-Host '::group::Build docs - Generate markdown help - Raw'
    Import-PSModule -Path $ModuleOutputFolder
    Write-Host ($ModuleName | Get-Module)
    $null = New-MarkdownHelp -Module $ModuleName -OutputFolder $DocsOutputFolder -Force -Verbose
    Get-ChildItem -Path $DocsOutputFolder -Recurse -Force -Include '*.md' | ForEach-Object {
        $fileName = $_.Name
        Write-Host "::group:: - [$fileName]"
        Show-FileContent -Path $_
    }

    Write-Host '::group::Build docs - Fix markdown code blocks'
    Get-ChildItem -Path $DocsOutputFolder -Recurse -Force -Include '*.md' | ForEach-Object {
        $content = Get-Content -Path $_.FullName
        $fixedOpening = $false
        $newContent = @()
        foreach ($line in $content) {
            if ($line -match '^```$' -and -not $fixedOpening) {
                $line = $line -replace '^```$', '```powershell'
                $fixedOpening = $true
            } elseif ($line -match '^```.+$') {
                $fixedOpening = $true
            } elseif ($line -match '^```$') {
                $fixedOpening = $false
            }
            $newContent += $line
        }
        $newContent | Set-Content -Path $_.FullName
    }

    Write-Host '::group::Build docs - Fix markdown escape characters'
    Get-ChildItem -Path $DocsOutputFolder -Recurse -Force -Include '*.md' | ForEach-Object {
        $content = Get-Content -Path $_.FullName -Raw
        $content = $content -replace '\\`', '`'
        $content = $content -replace '\\\[', '['
        $content = $content -replace '\\\]', ']'
        $content = $content -replace '\\\<', '<'
        $content = $content -replace '\\\>', '>'
        $content = $content -replace '\\\\', '\'
        $content | Set-Content -Path $_.FullName
    }

    Write-Host '::group::Build docs - Structure markdown files to match source files'
    $PublicFunctionsFolder = Join-Path $ModuleSourceFolder.FullName 'functions\public' | Get-Item
    Get-ChildItem -Path $DocsOutputFolder -Recurse -Force -Include '*.md' | ForEach-Object {
        $file = $_
        $relPath = [System.IO.Path]::GetRelativePath($DocsOutputFolder.FullName, $file.FullName)
        Write-Host " - $relPath"
        Write-Host "   Path:     $file"

        # find the source code file that matches the markdown file
        $scriptPath = Get-ChildItem -Path $PublicFunctionsFolder -Recurse -Force | Where-Object { $_.Name -eq ($file.BaseName + '.ps1') }
        Write-Host "   PS1 path: $scriptPath"
        $docsFilePath = ($scriptPath.FullName).Replace($PublicFunctionsFolder.FullName, $DocsOutputFolder.FullName).Replace('.ps1', '.md')
        Write-Host "   MD path:  $docsFilePath"
        $docsFolderPath = Split-Path -Path $docsFilePath -Parent
        $null = New-Item -Path $docsFolderPath -ItemType Directory -Force
        Move-Item -Path $file.FullName -Destination $docsFilePath -Force
    }

    Write-Host '::group::Build docs - Move markdown files from source files to docs'
    Get-ChildItem -Path $PublicFunctionsFolder -Recurse -Force -Include '*.md' | ForEach-Object {
        $file = $_
        $relPath = [System.IO.Path]::GetRelativePath($PublicFunctionsFolder.FullName, $file.FullName)
        Write-Host " - $relPath"
        Write-Host "   Path:     $file"

        $docsFilePath = ($file.FullName).Replace($PublicFunctionsFolder.FullName, $DocsOutputFolder.FullName)
        Write-Host "   MD path:  $docsFilePath"
        $docsFolderPath = Split-Path -Path $docsFilePath -Parent
        $null = New-Item -Path $docsFolderPath -ItemType Directory -Force
        Move-Item -Path $file.FullName -Destination $docsFilePath -Force
    }

    Write-Host '────────────────────────────────────────────────────────────────────────────────'
    Get-ChildItem -Path $DocsOutputFolder -Recurse -Force -Include '*.md' | ForEach-Object {
        $fileName = $_.Name
        Write-Host "::group:: - [$fileName]"
        Show-FileContent -Path $_
    }
}

function Build-PSModuleManifest {
    <#
        .SYNOPSIS
        Compiles the module manifest.

        .DESCRIPTION
        This function will compile the module manifest.
        It will generate the module manifest file and copy it to the output folder.

        .EXAMPLE
        Build-PSModuleManifest -SourceFolderPath 'C:\MyModule\src\MyModule' -OutputFolderPath 'C:\MyModule\build\MyModule'
    #>
    [CmdletBinding()]
    param(
        # Name of the module.
        [Parameter(Mandatory)]
        [string] $ModuleName,

        # Folder where the built modules are outputted. 'outputs/modules/MyModule'
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo] $ModuleOutputFolder
    )

    LogGroup 'Build manifest file' {
        $sourceManifestFilePath = Join-Path -Path $ModuleOutputFolder -ChildPath "$ModuleName.psd1"
        Write-Host "[SourceManifestFilePath] - [$sourceManifestFilePath]"
        if (-not (Test-Path -Path $sourceManifestFilePath)) {
            Write-Host "[SourceManifestFilePath] - [$sourceManifestFilePath] - Not found"
            $sourceManifestFilePath = Join-Path -Path $ModuleOutputFolder -ChildPath 'manifest.psd1'
        }
        if (-not (Test-Path -Path $sourceManifestFilePath)) {
            Write-Host "[SourceManifestFilePath] - [$sourceManifestFilePath] - Not found"
            $manifest = @{}
            Write-Host '[Manifest] - Loading empty manifest'
        } else {
            Write-Host "[SourceManifestFilePath] - [$sourceManifestFilePath] - Found"
            $manifest = Get-ModuleManifest -Path $sourceManifestFilePath -Verbose:$false
            Write-Host '[Manifest] - Loading from file'
            Remove-Item -Path $sourceManifestFilePath -Force -Verbose:$false
        }

        $rootModule = "$ModuleName.psm1"
        $manifest.RootModule = $rootModule
        Write-Host "[RootModule] - [$($manifest.RootModule)]"

        $manifest.ModuleVersion = '999.0.0'
        Write-Host "[ModuleVersion] - [$($manifest.ModuleVersion)]"

        $manifest.Author = $manifest.Keys -contains 'Author' ? ($manifest.Author | IsNotNullOrEmpty) ? $manifest.Author : $env:GITHUB_REPOSITORY_OWNER : $env:GITHUB_REPOSITORY_OWNER
        Write-Host "[Author] - [$($manifest.Author)]"

        $manifest.CompanyName = $manifest.Keys -contains 'CompanyName' ? ($manifest.CompanyName | IsNotNullOrEmpty) ? $manifest.CompanyName : $env:GITHUB_REPOSITORY_OWNER : $env:GITHUB_REPOSITORY_OWNER
        Write-Host "[CompanyName] - [$($manifest.CompanyName)]"

        $year = Get-Date -Format 'yyyy'
        $copyrightOwner = $manifest.CompanyName -eq $manifest.Author ? $manifest.Author : "$($manifest.Author) | $($manifest.CompanyName)"
        $copyright = "(c) $year $copyrightOwner. All rights reserved."
        $manifest.Copyright = $manifest.Keys -contains 'Copyright' ? -not [string]::IsNullOrEmpty($manifest.Copyright) ? $manifest.Copyright : $copyright : $copyright
        Write-Host "[Copyright] - [$($manifest.Copyright)]"

        $repoDescription = gh repo view --json description | ConvertFrom-Json | Select-Object -ExpandProperty description
        $manifest.Description = $manifest.Keys -contains 'Description' ? ($manifest.Description | IsNotNullOrEmpty) ? $manifest.Description : $repoDescription : $repoDescription
        Write-Host "[Description] - [$($manifest.Description)]"

        $manifest.PowerShellHostName = $manifest.Keys -contains 'PowerShellHostName' ? -not [string]::IsNullOrEmpty($manifest.PowerShellHostName) ? $manifest.PowerShellHostName : $null : $null
        Write-Host "[PowerShellHostName] - [$($manifest.PowerShellHostName)]"

        $manifest.PowerShellHostVersion = $manifest.Keys -contains 'PowerShellHostVersion' ? -not [string]::IsNullOrEmpty($manifest.PowerShellHostVersion) ? $manifest.PowerShellHostVersion : $null : $null
        Write-Host "[PowerShellHostVersion] - [$($manifest.PowerShellHostVersion)]"

        $manifest.DotNetFrameworkVersion = $manifest.Keys -contains 'DotNetFrameworkVersion' ? -not [string]::IsNullOrEmpty($manifest.DotNetFrameworkVersion) ? $manifest.DotNetFrameworkVersion : $null : $null
        Write-Host "[DotNetFrameworkVersion] - [$($manifest.DotNetFrameworkVersion)]"

        $manifest.ClrVersion = $manifest.Keys -contains 'ClrVersion' ? -not [string]::IsNullOrEmpty($manifest.ClrVersion) ? $manifest.ClrVersion : $null : $null
        Write-Host "[ClrVersion] - [$($manifest.ClrVersion)]"

        $manifest.ProcessorArchitecture = $manifest.Keys -contains 'ProcessorArchitecture' ? -not [string]::IsNullOrEmpty($manifest.ProcessorArchitecture) ? $manifest.ProcessorArchitecture : 'None' : 'None'
        Write-Host "[ProcessorArchitecture] - [$($manifest.ProcessorArchitecture)]"

        # Get the path separator for the current OS
        $pathSeparator = [System.IO.Path]::DirectorySeparatorChar

        Write-Host '[FileList]'
        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

        # Get files on module root
        $ModuleOutputFolder | Get-ChildItem -File -ErrorAction SilentlyContinue | Where-Object -Property Name -NotLike '*.ps1' |
            ForEach-Object { $files.Add($_) }

        # Get files on module subfolders, excluding the following folders 'init', 'classes', 'public', 'private'
        $skipList = @('init', 'classes', 'functions', 'variables')
        $ModuleOutputFolder | Get-ChildItem -Directory | Where-Object { $_.Name -NotIn $skipList } |
            Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $files.Add($_) }

        # Get the relative file path and store it in the manifest
        $files = $files | Select-Object -ExpandProperty FullName | ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart($pathSeparator) }
        $manifest.FileList = $files.count -eq 0 ? @() : @($files)
        $manifest.FileList | ForEach-Object { Write-Host "[FileList] - [$_]" }

        $requiredAssembliesFolderPath = Join-Path $ModuleOutputFolder 'assemblies'
        $nestedModulesFolderPath = Join-Path $ModuleOutputFolder 'modules'

        Write-Host '[RequiredAssemblies]'
        $existingRequiredAssemblies = $manifest.RequiredAssemblies
        $requiredAssemblies = Get-ChildItem -Path $requiredAssembliesFolderPath -Recurse -File -ErrorAction SilentlyContinue -Filter '*.dll' |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart([System.IO.Path]::DirectorySeparatorChar) }
        $requiredAssemblies += Get-ChildItem -Path $nestedModulesFolderPath -Recurse -Depth 1 -File -ErrorAction SilentlyContinue -Filter '*.dll' |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart([System.IO.Path]::DirectorySeparatorChar) }
        $manifest.RequiredAssemblies = if ($existingRequiredAssemblies) { $existingRequiredAssemblies } elseif ($requiredAssemblies.Count -gt 0) { @($requiredAssemblies) } else { @() }
        $manifest.RequiredAssemblies | ForEach-Object { Write-Host "[RequiredAssemblies] - [$_]" }

        Write-Host '[NestedModules]'
        $existingNestedModules = $manifest.NestedModules
        $nestedModules = Get-ChildItem -Path $nestedModulesFolderPath -Recurse -Depth 1 -File -ErrorAction SilentlyContinue -Include '*.psm1', '*.ps1', '*.dll' |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart([System.IO.Path]::DirectorySeparatorChar) }
        $manifest.NestedModules = if ($existingNestedModules) { $existingNestedModules } elseif ($nestedModules.Count -gt 0) { @($nestedModules) } else { @() }
        $manifest.NestedModules | ForEach-Object { Write-Host "[NestedModules] - [$_]" }

        Write-Host '[ScriptsToProcess]'
        $existingScriptsToProcess = $manifest.ScriptsToProcess
        $allScriptsToProcess = @('scripts') | ForEach-Object {
            Write-Host "[ScriptsToProcess] - Processing [$_]"
            $scriptsFolderPath = Join-Path $ModuleOutputFolder $_
            Get-ChildItem -Path $scriptsFolderPath -Recurse -File -ErrorAction SilentlyContinue -Include '*.ps1' | Select-Object -ExpandProperty FullName | ForEach-Object {
                $_.Replace($ModuleOutputFolder, '').TrimStart([System.IO.Path]::DirectorySeparatorChar) }
        }
        $manifest.ScriptsToProcess = if ($existingScriptsToProcess) { $existingScriptsToProcess } elseif ($allScriptsToProcess.Count -gt 0) { @($allScriptsToProcess) } else { @() }
        $manifest.ScriptsToProcess | ForEach-Object { Write-Host "[ScriptsToProcess] - [$_]" }

        Write-Host '[TypesToProcess]'
        $typesToProcess = Get-ChildItem -Path $ModuleOutputFolder -Recurse -File -ErrorAction SilentlyContinue -Include '*.Types.ps1xml' |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart($pathSeparator) }
        $manifest.TypesToProcess = $typesToProcess.count -eq 0 ? @() : @($typesToProcess)
        $manifest.TypesToProcess | ForEach-Object { Write-Host "[TypesToProcess] - [$_]" }

        Write-Host '[FormatsToProcess]'
        $formatsToProcess = Get-ChildItem -Path $ModuleOutputFolder -Recurse -File -ErrorAction SilentlyContinue -Include '*.Format.ps1xml' |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart($pathSeparator) }
        $manifest.FormatsToProcess = $formatsToProcess.count -eq 0 ? @() : @($formatsToProcess)
        $manifest.FormatsToProcess | ForEach-Object { Write-Host "[FormatsToProcess] - [$_]" }

        Write-Host '[DscResourcesToExport]'
        $dscResourcesToExportFolderPath = Join-Path $ModuleOutputFolder 'resources'
        $dscResourcesToExport = Get-ChildItem -Path $dscResourcesToExportFolderPath -Recurse -File -ErrorAction SilentlyContinue -Include '*.psm1' |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart($pathSeparator) }
        $manifest.DscResourcesToExport = $dscResourcesToExport.count -eq 0 ? @() : @($dscResourcesToExport)
        $manifest.DscResourcesToExport | ForEach-Object { Write-Host "[DscResourcesToExport] - [$_]" }

        $manifest.FunctionsToExport = Get-PSModuleFunctionsToExport -SourceFolderPath $ModuleOutputFolder
        $manifest.CmdletsToExport = Get-PSModuleCmdletsToExport -SourceFolderPath $ModuleOutputFolder
        $manifest.AliasesToExport = Get-PSModuleAliasesToExport -SourceFolderPath $ModuleOutputFolder
        $manifest.VariablesToExport = Get-PSModuleVariablesToExport -SourceFolderPath $ModuleOutputFolder

        Write-Host '[ModuleList]'
        $moduleList = Get-ChildItem -Path $ModuleOutputFolder -Recurse -File -ErrorAction SilentlyContinue -Include '*.psm1' | Where-Object -Property Name -NE $rootModule |
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Replace($ModuleOutputFolder, '').TrimStart($pathSeparator) }
        $manifest.ModuleList = $moduleList.count -eq 0 ? @() : @($moduleList)
        $manifest.ModuleList | ForEach-Object { Write-Host "[ModuleList] - [$_]" }

        Write-Host '[Gather]'
        $capturedModules = [System.Collections.Generic.List[System.Object]]::new()
        $capturedVersions = [System.Collections.Generic.List[string]]::new()
        $capturedPSEdition = [System.Collections.Generic.List[string]]::new()

        $files = $ModuleOutputFolder | Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue
        Write-Host "[Gather] - Processing [$($files.Count)] files"
        foreach ($file in $files) {
            $relativePath = $file.FullName.Replace($ModuleOutputFolder, '').TrimStart($pathSeparator)
            Write-Host "[Gather] - [$relativePath]"

            if ($file.extension -in '.psm1', '.ps1') {
                $fileContent = Get-Content -Path $file

                switch -Regex ($fileContent) {
                    # RequiredModules -> REQUIRES -Modules <Module-Name> | <Hashtable>, @() if not provided
                    '^\s*#Requires -Modules (.+)$' {
                        # Add captured module name to array
                        $capturedMatches = $matches[1].Split(',').trim()
                        $capturedMatches | ForEach-Object {
                            $hashtable = '@\{[^}]*\}'
                            if ($_ -match $hashtable) {
                                Write-Host " - [#Requires -Modules] - [$_] - Hashtable"
                            } else {
                                Write-Host " - [#Requires -Modules] - [$_] - String"
                            }
                            $capturedModules.Add($_)
                        }
                    }
                    # PowerShellVersion -> REQUIRES -Version <N>[.<n>], $null if not provided
                    '^\s*#Requires -Version (.+)$' {
                        Write-Host " - [#Requires -Version] - [$($matches[1])]"
                        $capturedVersions.Add($matches[1])
                    }
                    #CompatiblePSEditions -> REQUIRES -PSEdition <PSEdition-Name>, $null if not provided
                    '^\s*#Requires -PSEdition (.+)$' {
                        Write-Host " - [#Requires -PSEdition] - [$($matches[1])]"
                        $capturedPSEdition.Add($matches[1])
                    }
                }
            }
        }

        <#
            $test = [Microsoft.PowerShell.Commands.ModuleSpecification]::new()
            [Microsoft.PowerShell.Commands.ModuleSpecification]::TryParse("@{ModuleName = 'Az'; RequiredVersion = '5.0.0' }", [ref]$test)
            $test

            $test.ToString()

            $required = [Microsoft.PowerShell.Commands.ModuleSpecification]::new(@{ModuleName = 'Az'; RequiredVersion = '5.0.0' })
            $required.ToString()
        #>

        Write-Host '[RequiredModules] - Gathered'
        # Group the module specifications by ModuleName
        $capturedModules = $capturedModules | ForEach-Object {
            $test = [Microsoft.PowerShell.Commands.ModuleSpecification]::new()
            if ([Microsoft.PowerShell.Commands.ModuleSpecification]::TryParse($_, [ref]$test)) {
                $test
            } else {
                [Microsoft.PowerShell.Commands.ModuleSpecification]::new($_)
            }
        }

        $groupedModules = $capturedModules | Group-Object -Property Name

        # Initialize a list to store unique module specifications
        $uniqueModules = [System.Collections.Generic.List[System.Object]]::new()

        # Iterate through each group
        foreach ($group in $groupedModules) {
            $requiredModuleName = $group.Name
            Write-Host "Processing required module [$requiredModuleName]"
            $requiredVersion = $group.Group.RequiredVersion | ForEach-Object { [Version]$_ } | Sort-Object -Unique
            $minimumVersion = $group.Group.Version | ForEach-Object { [Version]$_ } | Sort-Object -Unique | Select-Object -Last 1
            $maximumVersion = $group.Group.MaximumVersion | ForEach-Object { [Version]$_ } | Sort-Object -Unique | Select-Object -First 1
            Write-Host "RequiredVersion: [$($requiredVersion -join ', ')]"
            Write-Host "ModuleVersion:   [$minimumVersion]"
            Write-Host "MaximumVersion:  [$maximumVersion]"

            if ($requiredVersion.Count -gt 1) {
                throw 'Multiple RequiredVersions specified.'
            }

            if (-not $minimumVersion) {
                $minimumVersion = [Version]'0.0.0'
            }

            if (-not $maximumVersion) {
                $maximumVersion = [Version]'9999.9999.9999'
            }

            if ($requiredVersion -and ($minimumVersion -gt $requiredVersion)) {
                throw 'ModuleVersion is higher than RequiredVersion.'
            }

            if ($minimumVersion -gt $maximumVersion) {
                throw 'ModuleVersion is higher than MaximumVersion.'
            }
            if ($requiredVersion -and ($requiredVersion -gt $maximumVersion)) {
                throw 'RequiredVersion is higher than MaximumVersion.'
            }

            if ($requiredVersion) {
                Write-Host '[RequiredModules] - RequiredVersion'
                $uniqueModule = @{
                    ModuleName      = $requiredModuleName
                    RequiredVersion = $requiredVersion
                }
            } elseif (($minimumVersion -ne [Version]'0.0.0') -or ($maximumVersion -ne [Version]'9999.9999.9999')) {
                Write-Host '[RequiredModules] - ModuleVersion/MaximumVersion'
                $uniqueModule = @{
                    ModuleName = $requiredModuleName
                }
                if ($minimumVersion -ne [Version]'0.0.0') {
                    $uniqueModule['ModuleVersion'] = $minimumVersion
                }
                if ($maximumVersion -ne [Version]'9999.9999.9999') {
                    $uniqueModule['MaximumVersion'] = $maximumVersion
                }
            } else {
                Write-Host '[RequiredModules] - Simple string'
                $uniqueModule = $requiredModuleName
            }
            $uniqueModules.Add([Microsoft.PowerShell.Commands.ModuleSpecification]::new($uniqueModule))
        }

        Write-Host '[RequiredModules] - Result'
        $manifest.RequiredModules = $uniqueModules
        $manifest.RequiredModules | ForEach-Object { Write-Host " - [$($_ | Out-String)]" }

        Write-Host '[PowerShellVersion]'
        $capturedVersions = $capturedVersions | Sort-Object -Unique -Descending
        $capturedVersions | ForEach-Object { Write-Host "[PowerShellVersion] - [$_]" }
        $manifest.PowerShellVersion = $capturedVersions.count -eq 0 ? [version]'5.1' : [version]($capturedVersions | Select-Object -First 1)
        Write-Host '[PowerShellVersion] - Selecting version'
        Write-Host "[PowerShellVersion] - [$($manifest.PowerShellVersion)]"

        Write-Host '[CompatiblePSEditions]'
        $capturedPSEdition = $capturedPSEdition | Sort-Object -Unique
        if ($capturedPSEdition.count -eq 2) {
            throw "Conflict detected: The module requires both 'Desktop' and 'Core' editions." +
            "'Desktop' and 'Core' editions cannot be required at the same time."
        }
        if ($capturedPSEdition.count -eq 0 -and $manifest.PowerShellVersion -gt '5.1') {
            Write-Host "[CompatiblePSEditions] - Defaulting to 'Core', as no PSEdition was specified and PowerShellVersion > 5.1"
            $capturedPSEdition = @('Core')
        }
        $manifest.CompatiblePSEditions = $capturedPSEdition.count -eq 0 ? @('Core', 'Desktop') : @($capturedPSEdition)
        $manifest.CompatiblePSEditions | ForEach-Object { Write-Host "[CompatiblePSEditions] - [$_]" }

        if ($manifest.PowerShellVersion -gt '5.1' -and $manifest.CompatiblePSEditions -contains 'Desktop') {
            throw "Conflict detected: The module requires PowerShellVersion > 5.1 while CompatiblePSEditions = 'Desktop'" +
            "'Desktop' edition is not supported for PowerShellVersion > 5.1"
        }

        Write-Host '[PrivateData]'
        $privateData = $manifest.Keys -contains 'PrivateData' ? $null -ne $manifest.PrivateData ? $manifest.PrivateData : @{} : @{}
        if ($manifest.Keys -contains 'PrivateData') {
            $manifest.Remove('PrivateData')
        }

        Write-Host '[HelpInfoURI]'
        $manifest.HelpInfoURI = $privateData.Keys -contains 'HelpInfoURI' ? $null -ne $privateData.HelpInfoURI ? $privateData.HelpInfoURI : '' : ''
        Write-Host "[HelpInfoURI] - [$($manifest.HelpInfoURI)]"
        if ([string]::IsNullOrEmpty($manifest.HelpInfoURI)) {
            $manifest.Remove('HelpInfoURI')
        }

        Write-Host '[DefaultCommandPrefix]'
        $manifest.DefaultCommandPrefix = $privateData.Keys -contains 'DefaultCommandPrefix' ? $null -ne $privateData.DefaultCommandPrefix ? $privateData.DefaultCommandPrefix : '' : ''
        Write-Host "[DefaultCommandPrefix] - [$($manifest.DefaultCommandPrefix)]"

        $PSData = $privateData.Keys -contains 'PSData' ? $null -ne $privateData.PSData ? $privateData.PSData : @{} : @{}

        Write-Host '[Tags]'
        try {
            $repoLabels = gh repo view --json repositoryTopics | ConvertFrom-Json | Select-Object -ExpandProperty repositoryTopics | Select-Object -ExpandProperty name
        } catch {
            $repoLabels = @()
        }
        $manifestTags = [System.Collections.Generic.List[string]]::new()
        $tags = $PSData.Keys -contains 'Tags' ? ($PSData.Tags).Count -gt 0 ? $PSData.Tags : $repoLabels : $repoLabels
        $tags | ForEach-Object { $manifestTags.Add($_) }
        # Add tags for compatability mode. https://docs.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest?view=powershell-7.1#compatibility-tags
        if ($manifest.CompatiblePSEditions -contains 'Desktop') {
            if ($manifestTags -notcontains 'PSEdition_Desktop') {
                $manifestTags.Add('PSEdition_Desktop')
            }
        }
        if ($manifest.CompatiblePSEditions -contains 'Core') {
            if ($manifestTags -notcontains 'PSEdition_Core') {
                $manifestTags.Add('PSEdition_Core')
            }
        }
        $manifestTags | ForEach-Object { Write-Host "[Tags] - [$_]" }
        $manifest.Tags = $manifestTags

        if ($PSData.Tags -contains 'PSEdition_Core' -and $manifest.PowerShellVersion -lt '6.0') {
            throw "[Tags] - Cannot be PSEdition = 'Core' and PowerShellVersion < 6.0"
        }
        <#
            Windows: Packages that are compatible with the Windows Operating System
            Linux: Packages that are compatible with Linux Operating Systems
            MacOS: Packages that are compatible with the Mac Operating System
            https://learn.microsoft.com/en-us/powershell/gallery/concepts/package-manifest-affecting-ui?view=powershellget-2.x#tag-details
        #>

        Write-Host '[LicenseUri]'
        $licenseUri = "https://github.com/$env:GITHUB_REPOSITORY_OWNER/$env:GITHUB_REPOSITORY_NAME/blob/main/LICENSE"
        $manifest.LicenseUri = $PSData.Keys -contains 'LicenseUri' ? $null -ne $PSData.LicenseUri ? $PSData.LicenseUri : $licenseUri : $licenseUri
        Write-Host "[LicenseUri] - [$($manifest.LicenseUri)]"
        if ([string]::IsNullOrEmpty($manifest.LicenseUri)) {
            $manifest.Remove('LicenseUri')
        }

        Write-Host '[ProjectUri]'
        $projectUri = gh repo view --json url | ConvertFrom-Json | Select-Object -ExpandProperty url
        $manifest.ProjectUri = $PSData.Keys -contains 'ProjectUri' ? $null -ne $PSData.ProjectUri ? $PSData.ProjectUri : $projectUri : $projectUri
        Write-Host "[ProjectUri] - [$($manifest.ProjectUri)]"
        if ([string]::IsNullOrEmpty($manifest.ProjectUri)) {
            $manifest.Remove('ProjectUri')
        }

        Write-Host '[IconUri]'
        $iconUri = "https://raw.githubusercontent.com/$env:GITHUB_REPOSITORY_OWNER/$env:GITHUB_REPOSITORY_NAME/main/icon/icon.png"
        $manifest.IconUri = $PSData.Keys -contains 'IconUri' ? $null -ne $PSData.IconUri ? $PSData.IconUri : $iconUri : $iconUri
        Write-Host "[IconUri] - [$($manifest.IconUri)]"
        if ([string]::IsNullOrEmpty($manifest.IconUri)) {
            $manifest.Remove('IconUri')
        }

        Write-Host '[ReleaseNotes]'
        $manifest.ReleaseNotes = $PSData.Keys -contains 'ReleaseNotes' ? $null -ne $PSData.ReleaseNotes ? $PSData.ReleaseNotes : '' : ''
        Write-Host "[ReleaseNotes] - [$($manifest.ReleaseNotes)]"
        if ([string]::IsNullOrEmpty($manifest.ReleaseNotes)) {
            $manifest.Remove('ReleaseNotes')
        }

        Write-Host '[PreRelease]'
        # $manifest.PreRelease = ""
        # Is managed by the publish action

        Write-Host '[RequireLicenseAcceptance]'
        $manifest.RequireLicenseAcceptance = $PSData.Keys -contains 'RequireLicenseAcceptance' ? $null -ne $PSData.RequireLicenseAcceptance ? $PSData.RequireLicenseAcceptance : $false : $false
        Write-Host "[RequireLicenseAcceptance] - [$($manifest.RequireLicenseAcceptance)]"
        if ($manifest.RequireLicenseAcceptance -eq $false) {
            $manifest.Remove('RequireLicenseAcceptance')
        }

        Write-Host '[ExternalModuleDependencies]'
        $manifest.ExternalModuleDependencies = $PSData.Keys -contains 'ExternalModuleDependencies' ? $null -ne $PSData.ExternalModuleDependencies ? $PSData.ExternalModuleDependencies : @() : @()
        if (($manifest.ExternalModuleDependencies).count -eq 0) {
            $manifest.Remove('ExternalModuleDependencies')
        } else {
            $manifest.ExternalModuleDependencies | ForEach-Object { Write-Host "[ExternalModuleDependencies] - [$_]" }
        }

        Write-Host 'Creating new manifest file in outputs folder'
        $outputManifestPath = Join-Path -Path $ModuleOutputFolder -ChildPath "$ModuleName.psd1"
        Write-Host "OutputManifestPath - [$outputManifestPath]"
        New-ModuleManifest -Path $outputManifestPath @manifest
    }

    LogGroup 'Build manifest file - Result - Before format' {
        Show-FileContent -Path $outputManifestPath
    }

    LogGroup 'Build manifest file - Format' {
        Set-ModuleManifest -Path $outputManifestPath
    }

    LogGroup 'Build manifest file - Result - After format' {
        Show-FileContent -Path $outputManifestPath
    }

    LogGroup 'Build manifest file - Validate - Install module dependencies' {
        Resolve-PSModuleDependency -ManifestFilePath $outputManifestPath
    }

    LogGroup 'Build manifest file - Validate - Test manifest file' {
        Test-ModuleManifest -Path $outputManifestPath | Format-List | Out-String
    }
}

function Build-PSModuleRootModule {
    <#
        .SYNOPSIS
        Compiles the module root module files.

        .DESCRIPTION
        This function will compile the modules root module from source files.
        It will copy the source files to the output folder and start compiling the module.
        During compilation, the source files are added to the root module file in the following order:

        1. Module header from header.ps1 file. Usually to suppress code analysis warnings/errors and to add [CmdletBinding()] to the module.
        2. Data loader is added if data files are available.
        3. Combines *.ps1 files from the following folders in alphabetical order from each folder:
            1. init
            2. classes/private
            3. classes/public
            4. functions/private
            5. functions/public
            6. variables/private
            7. variables/public
            8. Any remaining *.ps1 on module root.
        4. Adds a class loader for classes found in the classes/public folder.
        5. Export-ModuleMember by using the functions, cmdlets, variables and aliases found in the source files.
            - `Functions` will only contain functions that are from the `functions/public` folder.
            - `Cmdlets` will only contain cmdlets that are from the `cmdlets/public` folder.
            - `Variables` will only contain variables that are from the `variables/public` folder.
            - `Aliases` will only contain aliases that are from the functions from the `functions/public` folder.

        .EXAMPLE
        Build-PSModuleRootModule -SourceFolderPath 'C:\MyModule\src\MyModule' -OutputFolderPath 'C:\MyModule\build\MyModule'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '', Scope = 'Function',
        Justification = 'LogGroup - Scoping affects the variables line of sight.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '', Scope = 'Function',
        Justification = 'Want to just write to the console, not the pipeline.'
    )]
    [CmdletBinding()]
    param(
        # Name of the module.
        [Parameter(Mandatory)]
        [string] $ModuleName,

        # Folder where the built modules are outputted. 'outputs/modules/MyModule'
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo] $ModuleOutputFolder
    )

    # Get the path separator for the current OS
    $pathSeparator = [System.IO.Path]::DirectorySeparatorChar

    LogGroup 'Build root module' {
        $rootModuleFile = New-Item -Path $ModuleOutputFolder -Name "$ModuleName.psm1" -Force

        #region - Analyze source files

        #region - Export-Classes
        $classesFolder = Join-Path -Path $ModuleOutputFolder -ChildPath 'classes/public'
        $classExports = ''
        if (Test-Path -Path $classesFolder) {
            $classes = Get-PSModuleClassesToExport -SourceFolderPath $classesFolder
            if ($classes.count -gt 0) {
                $classExports += @'
#region    Class exporter
# Get the internal TypeAccelerators class to use its static methods.
$TypeAcceleratorsClass = [psobject].Assembly.GetType(
    'System.Management.Automation.TypeAccelerators'
)
# Ensure none of the types would clobber an existing type accelerator.
# If a type accelerator with the same name exists, throw an exception.
$ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
# Define the types to export with type accelerators.
$ExportableEnums = @(

'@
                $classes | Where-Object Type -EQ 'enum' | ForEach-Object {
                    $classExports += "    [$($_.Name)]`n"
                }

                $classExports += @'
)
$ExportableEnums | Foreach-Object { Write-Verbose "Exporting enum '$($_.FullName)'." }
foreach ($Type in $ExportableEnums) {
    if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
        Write-Verbose "Enum already exists [$($Type.FullName)]. Skipping."
    } else {
        Write-Verbose "Importing enum '$Type'."
        $TypeAcceleratorsClass::Add($Type.FullName, $Type)
    }
}
$ExportableClasses = @(

'@
                $classes | Where-Object Type -EQ 'class' | ForEach-Object {
                    $classExports += "    [$($_.Name)]`n"
                }

                $classExports += @'
)
$ExportableClasses | Foreach-Object { Write-Verbose "Exporting class '$($_.FullName)'." }
foreach ($Type in $ExportableClasses) {
    if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
        Write-Verbose "Class already exists [$($Type.FullName)]. Skipping."
    } else {
        Write-Verbose "Importing class '$Type'."
        $TypeAcceleratorsClass::Add($Type.FullName, $Type)
    }
}

# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    foreach ($Type in ($ExportableEnums + $ExportableClasses)) {
        $TypeAcceleratorsClass::Remove($Type.FullName)
    }
}.GetNewClosure()
#endregion Class exporter
'@
            }
        }
        #endregion - Export-Classes

        $exports = [System.Collections.Specialized.OrderedDictionary]::new()
        $exports.Add('Alias', (Get-PSModuleAliasesToExport -SourceFolderPath $ModuleOutputFolder))
        $exports.Add('Cmdlet', (Get-PSModuleCmdletsToExport -SourceFolderPath $ModuleOutputFolder))
        $exports.Add('Function', (Get-PSModuleFunctionsToExport -SourceFolderPath $ModuleOutputFolder))
        $exports.Add('Variable', (Get-PSModuleVariablesToExport -SourceFolderPath $ModuleOutputFolder))

        [pscustomobject]$exports | Format-List | Out-String
        #endregion - Analyze source files

        #region - Module header
        $headerFilePath = Join-Path -Path $ModuleOutputFolder -ChildPath 'header.ps1'
        if (Test-Path -Path $headerFilePath) {
            Get-Content -Path $headerFilePath -Raw | Add-Content -Path $rootModuleFile -Force
            $headerFilePath | Remove-Item -Force
        } else {
            Add-Content -Path $rootModuleFile -Force -Value @'
[CmdletBinding()]
param()
'@
        }
        #endregion - Module header

        #region - Module post-header
        Add-Content -Path $rootModuleFile -Force -Value @'
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$script:PSModuleInfo = Test-ModuleManifest -Path "$PSScriptRoot\$baseName.psd1"
$script:PSModuleInfo | Format-List | Out-String -Stream | ForEach-Object { Write-Debug $_ }
$scriptName = $script:PSModuleInfo.Name
Write-Debug "[$scriptName] - Importing module"
'@
        #endregion - Module post-header

        #region - Data loader
        if (Test-Path -Path (Join-Path -Path $ModuleOutputFolder -ChildPath 'data')) {

            Add-Content -Path $rootModuleFile.FullName -Force -Value @'
#region    Data importer
Write-Debug "[$scriptName] - [data] - Processing folder"
$dataFolder = (Join-Path $PSScriptRoot 'data')
Write-Debug "[$scriptName] - [data] - [$dataFolder]"
Get-ChildItem -Path "$dataFolder" -Recurse -Force -Include '*.psd1' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Debug "[$scriptName] - [data] - [$($_.BaseName)] - Importing"
    New-Variable -Name $_.BaseName -Value (Import-PowerShellDataFile -Path $_.FullName) -Force
    Write-Debug "[$scriptName] - [data] - [$($_.BaseName)] - Done"
}
Write-Debug "[$scriptName] - [data] - Done"
#endregion Data importer
'@
        }
        #endregion - Data loader

        #region - Add content from subfolders
        $scriptFoldersToProcess = @(
            'init',
            'classes/private',
            'classes/public',
            'functions/private',
            'functions/public',
            'variables/private',
            'variables/public'
        )

        foreach ($scriptFolder in $scriptFoldersToProcess) {
            $scriptFolder = Join-Path -Path $ModuleOutputFolder -ChildPath $scriptFolder
            if (-not (Test-Path -Path $scriptFolder)) {
                continue
            }
            Add-ContentFromItem -Path $scriptFolder -RootModuleFilePath $rootModuleFile -RootPath $ModuleOutputFolder
            Remove-Item -Path $scriptFolder -Force -Recurse
        }
        #endregion - Add content from subfolders

        #region - Add content from *.ps1 files on module root
        $files = $ModuleOutputFolder | Get-ChildItem -File -Force -Filter '*.ps1' | Sort-Object -Property FullName
        foreach ($file in $files) {
            $relativePath = $file.FullName -Replace $ModuleOutputFolder, ''
            $relativePath = $relativePath -Replace $file.Extension, ''
            $relativePath = $relativePath.TrimStart($pathSeparator)
            $relativePath = $relativePath -Split $pathSeparator | ForEach-Object { "[$_]" }
            $relativePath = $relativePath -Join ' - '

            Add-Content -Path $rootModuleFile -Force -Value @"
#region    $relativePath
Write-Debug "[`$scriptName] - $relativePath - Importing"
"@
            Get-Content -Path $file.FullName | Add-Content -Path $rootModuleFile -Force

            Add-Content -Path $rootModuleFile -Force -Value @"
Write-Debug "[`$scriptName] - $relativePath - Done"
#endregion $relativePath
"@
            $file | Remove-Item -Force
        }
        #endregion - Add content from *.ps1 files on module root

        #region - Export-ModuleMember
        Add-Content -Path $rootModuleFile -Force -Value $classExports

        $exportsString = $exports | Format-Hashtable

        $exportsString | Out-String

        $params = @{
            Path  = $rootModuleFile
            Force = $true
            Value = @"
#region    Member exporter
`$exports = $exportsString
Export-ModuleMember @exports
#endregion Member exporter
"@
        }
        Add-Content @params
        #endregion - Export-ModuleMember

    }

    LogGroup 'Build root module - Result - Before format' {
        Write-Host (Show-FileContent -Path $rootModuleFile)
    }

    LogGroup 'Build root module - Format' {
        $AllContent = Get-Content -Path $rootModuleFile -Raw
        $settings = Join-Path -Path $PSScriptRoot 'PSScriptAnalyzer.Tests.psd1'
        Invoke-Formatter -ScriptDefinition $AllContent -Settings $settings |
            Out-File -FilePath $rootModuleFile -Encoding utf8BOM -Force
    }

    LogGroup 'Build root module - Result - After format' {
        Write-Host (Show-FileContent -Path $rootModuleFile)
    }

    LogGroup 'Build root module - Validate - Import' {
        Add-PSModulePath -Path (Split-Path -Path $ModuleOutputFolder -Parent)
        Import-PSModule -Path $ModuleOutputFolder
    }

    LogGroup 'Build root module - Validate - File list' {
        Get-ChildItem -Path $ModuleOutputFolder -Recurse -Force | Resolve-Path -Relative | Sort-Object
    }
}

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

function Get-PSModuleAliasesToExport {
    <#
        .SYNOPSIS
        Gets the aliases to export from the module manifest.

        .DESCRIPTION
        This function will get the aliases to export from the module manifest.

        .EXAMPLE
        Get-PSModuleAliasesToExport -SourceFolderPath 'C:\MyModule\src\MyModule'
    #>
    [CmdletBinding()]
    param(
        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [string] $SourceFolderPath
    )

    $manifestPropertyName = 'AliasesToExport'

    $moduleName = Split-Path -Path $SourceFolderPath -Leaf
    $manifestFileName = "$moduleName.psd1"
    $manifestFilePath = Join-Path -Path $SourceFolderPath $manifestFileName

    $manifest = Get-ModuleManifest -Path $manifestFilePath -Verbose:$false

    Write-Host "[$manifestPropertyName]"
    $aliasesToExport = (($manifest.AliasesToExport).count -eq 0) -or ($manifest.AliasesToExport | IsNullOrEmpty) ? '*' : $manifest.AliasesToExport
    $aliasesToExport | ForEach-Object {
        Write-Host "[$manifestPropertyName] - [$_]"
    }

    $aliasesToExport
}

function Get-PSModuleClassesToExport {
    <#
        .SYNOPSIS
        Gets the classes to export from the module source code.

        .DESCRIPTION
        This function will get the classes to export from the module source code.

        .EXAMPLE
        Get-PSModuleClassesToExport -SourceFolderPath 'C:\MyModule\src\MyModule'

        Book
        BookList

        This will return the classes to export from the module source code.

        .NOTES
        Inspired by [about_Classes | Exporting classes with type accelerators](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-7.4#exporting-classes-with-type-accelerators)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidLongLines', '', Justification = 'Contains long links.')]
    [CmdletBinding()]
    param (
        # The path to the module root folder.
        [Parameter(Mandatory)]
        [string] $SourceFolderPath
    )

    $files = Get-ChildItem -Path $SourceFolderPath -Recurse -Include '*.ps1' | Sort-Object -Property FullName

    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw
        $stringMatches = [Regex]::Matches($content, '(?i)^(class|enum)\s+([^\s{]+)', 'Multiline')
        foreach ($match in $stringMatches) {
            [pscustomobject]@{
                Type = $match.Groups[1].Value
                Name = $match.Groups[2].Value
            }
        }
    }
}

function Get-PSModuleCmdletsToExport {
    <#
        .SYNOPSIS
        Gets the cmdlets to export from the module manifest.

        .DESCRIPTION
        This function will get the cmdlets to export from the module manifest.

        .EXAMPLE
        Get-PSModuleCmdletsToExport -SourceFolderPath 'C:\MyModule\src\MyModule'
    #>
    [CmdletBinding()]
    param(
        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [string] $SourceFolderPath
    )

    $manifestPropertyName = 'CmdletsToExport'

    $moduleName = Split-Path -Path $SourceFolderPath -Leaf
    $manifestFileName = "$moduleName.psd1"
    $manifestFilePath = Join-Path -Path $SourceFolderPath $manifestFileName

    $manifest = Get-ModuleManifest -Path $manifestFilePath -Verbose:$false

    Write-Host "[$manifestPropertyName]"
    $cmdletsToExport = (($manifest.CmdletsToExport).count -eq 0) -or ($manifest.CmdletsToExport | IsNullOrEmpty) ? '' : $manifest.CmdletsToExport
    $cmdletsToExport | ForEach-Object {
        Write-Host "[$manifestPropertyName] - [$_]"
    }

    $cmdletsToExport
}

function Get-PSModuleFunctionsToExport {
    <#
        .SYNOPSIS
        Gets the functions to export from the module manifest.

        .DESCRIPTION
        This function will get the functions to export from the module manifest.

        .EXAMPLE
        Get-PSModuleFunctionsToExport -SourceFolderPath 'C:\MyModule\src\MyModule'
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [string] $SourceFolderPath
    )

    $manifestPropertyName = 'FunctionsToExport'

    Write-Host "[$manifestPropertyName]"
    Write-Host "[$manifestPropertyName] - Checking path for functions and filters"

    $publicFolderPath = Join-Path -Path $SourceFolderPath -ChildPath 'functions/public'
    if (-not (Test-Path -Path $publicFolderPath -PathType Container)) {
        Write-Host "[$manifestPropertyName] - [Folder not found] - [$publicFolderPath]"
        return $functionsToExport
    }
    Write-Host "[$manifestPropertyName] - [$publicFolderPath]"
    $functionsToExport = [Collections.Generic.List[string]]::new()
    $scriptFiles = Get-ChildItem -Path $publicFolderPath -Recurse -File -ErrorAction SilentlyContinue -Include '*.ps1'
    Write-Host "[$manifestPropertyName] - [$($scriptFiles.Count)]"
    foreach ($file in $scriptFiles) {
        $fileContent = Get-Content -Path $file.FullName -Raw
        $containsFunction = ($fileContent -match 'function ') -or ($fileContent -match 'filter ')
        Write-Host "[$manifestPropertyName] - [$($file.BaseName)] - [$containsFunction]"
        if ($containsFunction) {
            $functionsToExport.Add($file.BaseName)
        }
    }

    [array]$functionsToExport
}

function Get-PSModuleVariablesToExport {
    <#
        .SYNOPSIS
        Gets the variables to export from the module manifest.

        .DESCRIPTION
        This function will get the variables to export from the module manifest.

        .EXAMPLE
        Get-PSModuleVariablesToExport -SourceFolderPath 'C:\MyModule\src\MyModule'
    #>
    [OutputType([string])]
    [OutputType([Collections.Generic.List[string]])]
    [CmdletBinding()]
    param(
        # Path to the folder where the module source code is located.
        [Parameter(Mandatory)]
        [string] $SourceFolderPath
    )

    $manifestPropertyName = 'VariablesToExport'

    Write-Host "[$manifestPropertyName]"

    $variablesToExport = [Collections.Generic.List[string]]::new()
    $variableFolderPath = Join-Path -Path $SourceFolderPath -ChildPath 'variables/public'
    if (-not (Test-Path -Path $variableFolderPath -PathType Container)) {
        Write-Host "[$manifestPropertyName] - [Folder not found] - [$variableFolderPath]"
        return ''
    }
    $scriptFilePaths = Get-ChildItem -Path $variableFolderPath -Recurse -File -Filter *.ps1 | Select-Object -ExpandProperty FullName

    $scriptFilePaths | ForEach-Object {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_, [ref]$null, [ref]$null)
        $variables = Get-RootLevelVariable -Ast $ast
        $variables | ForEach-Object {
            $variablesToExport.Add($_)
        }
    }

    $variablesToExport | ForEach-Object {
        Write-Host "[$manifestPropertyName] - [$_]"
    }

    $variablesToExport
}

function Get-RootLevelVariable {
    <#
        .SYNOPSIS
        Get the root-level variables in a ast.

        .EXAMPLE
        Get-RootLevelVariable -Ast $ast
    #>
    [CmdletBinding()]
    param (
        # The Abstract Syntax Tree (AST) to analyze
        [System.Management.Automation.Language.ScriptBlockAst]$Ast
    )
    # Iterate over the top-level statements in the AST
    foreach ($statement in $Ast.EndBlock.Statements) {
        # Check if the statement is an assignment statement
        if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            # Get the variable name, removing the scope prefix
            $statement.Left.VariablePath.UserPath -replace '.*:'
        }
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

function Publish-PSModule {
    <#
    .SYNOPSIS
    Publishes a module to the PowerShell Gallery and GitHub Pages.

    .DESCRIPTION
    Publishes a module to the PowerShell Gallery and GitHub Pages.

    .EXAMPLE
    Publish-PSModule -Name 'PSModule.FX' -APIKey $env:PSGALLERY_API_KEY
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseDeclaredVarsMoreThanAssignments', '',
        Justification = 'LogGroup - Scoping affects the variables line of sight.'
    )]
    [OutputType([void])]
    [CmdletBinding()]
    param(
        # Name of the module to process.
        [Parameter()]
        [string] $Name,

        # The path to the module to process.
        [Parameter(Mandatory)]
        [string] $ModulePath,

        # The API key for the destination repository.
        [Parameter(Mandatory)]
        [string] $APIKey
    )

    LogGroup 'Set configuration' {
        if (-not (Test-Path -Path $env:PSMODULE_PUBLISH_PSMODULE_INPUT_ConfigurationFile -PathType Leaf)) {
            Write-Output "Configuration file not found at [$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ConfigurationFile]"
        } else {
            Write-Output "Reading from configuration file [$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ConfigurationFile]"
            $configuration = ConvertFrom-Yaml -Yaml (Get-Content $env:PSMODULE_PUBLISH_PSMODULE_INPUT_ConfigurationFile -Raw)
        }

        $autoCleanup = ($configuration.AutoCleanup | IsNotNullOrEmpty) ?
        $configuration.AutoCleanup -eq 'true' :
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_AutoCleanup -eq 'true'
        $autoPatching = ($configuration.AutoPatching | IsNotNullOrEmpty) ?
        $configuration.AutoPatching -eq 'true' :
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_AutoPatching -eq 'true'
        $datePrereleaseFormat = ($configuration.DatePrereleaseFormat | IsNotNullOrEmpty) ?
        $configuration.DatePrereleaseFormat :
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_DatePrereleaseFormat
        $incrementalPrerelease = ($configuration.IncrementalPrerelease | IsNotNullOrEmpty) ?
        $configuration.IncrementalPrerelease -eq 'true' :
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_IncrementalPrerelease -eq 'true'
        $versionPrefix = ($configuration.VersionPrefix | IsNotNullOrEmpty) ?
        $configuration.VersionPrefix :
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_VersionPrefix
        $whatIf = ($configuration.WhatIf | IsNotNullOrEmpty) ?
        $configuration.WhatIf -eq 'true' :
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WhatIf -eq 'true'

        $ignoreLabels = (($configuration.IgnoreLabels | IsNotNullOrEmpty) ?
            $configuration.IgnoreLabels :
            $env:PSMODULE_PUBLISH_PSMODULE_INPUT_IgnoreLabels) -split ',' | ForEach-Object { $_.Trim() }
        $majorLabels = (($configuration.MajorLabels | IsNotNullOrEmpty) ?
            $configuration.MajorLabels :
            $env:PSMODULE_PUBLISH_PSMODULE_INPUT_MajorLabels) -split ',' | ForEach-Object { $_.Trim() }
        $minorLabels = (($configuration.MinorLabels | IsNotNullOrEmpty) ?
            $configuration.MinorLabels :
            $env:PSMODULE_PUBLISH_PSMODULE_INPUT_MinorLabels) -split ',' | ForEach-Object { $_.Trim() }
        $patchLabels = (($configuration.PatchLabels | IsNotNullOrEmpty) ?
            $configuration.PatchLabels :
            $env:PSMODULE_PUBLISH_PSMODULE_INPUT_PatchLabels) -split ',' | ForEach-Object { $_.Trim() }

        Write-Output '-------------------------------------------------'
        Write-Output "Auto cleanup enabled:           [$autoCleanup]"
        Write-Output "Auto patching enabled:          [$autoPatching]"
        Write-Output "Date-based prerelease format:   [$datePrereleaseFormat]"
        Write-Output "Incremental prerelease enabled: [$incrementalPrerelease]"
        Write-Output "Version prefix:                 [$versionPrefix]"
        Write-Output "What if mode:                   [$whatIf]"
        Write-Output ''
        Write-Output "Ignore labels:                  [$($ignoreLabels -join ', ')]"
        Write-Output "Major labels:                   [$($majorLabels -join ', ')]"
        Write-Output "Minor labels:                   [$($minorLabels -join ', ')]"
        Write-Output "Patch labels:                   [$($patchLabels -join ', ')]"
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Event information - JSON' {
        $githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
        $githubEventJson | Format-List | Out-String
    }

    LogGroup 'Event information - Object' {
        $githubEvent = $githubEventJson | ConvertFrom-Json
        $pull_request = $githubEvent.pull_request
        $githubEvent | Format-List | Out-String
    }

    LogGroup 'Event information - Details' {
        $defaultBranchName = (gh repo view --json defaultBranchRef | ConvertFrom-Json | Select-Object -ExpandProperty defaultBranchRef).name
        $isPullRequest = $githubEvent.PSObject.Properties.Name -Contains 'pull_request'
        if (-not ($isPullRequest -or $whatIf)) {
            Write-Warning '⚠️ A release should not be created in this context. Exiting.'
            exit
        }
        $actionType = $githubEvent.action
        $isMerged = $pull_request.merged -eq 'True'
        $prIsClosed = $pull_request.state -eq 'closed'
        $prBaseRef = $pull_request.base.ref
        $prHeadRef = $pull_request.head.ref
        $targetIsDefaultBranch = $pull_request.base.ref -eq $defaultBranchName

        Write-Output '-------------------------------------------------'
        Write-Output "Default branch:                 [$defaultBranchName]"
        Write-Output "Is a pull request event:        [$isPullRequest]"
        Write-Output "Action type:                    [$actionType]"
        Write-Output "PR Merged:                      [$isMerged]"
        Write-Output "PR Closed:                      [$prIsClosed]"
        Write-Output "PR Base Ref:                    [$prBaseRef]"
        Write-Output "PR Head Ref:                    [$prHeadRef]"
        Write-Output "Target is default branch:       [$targetIsDefaultBranch]"
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Pull request - details' {
        $pull_request | Format-List | Out-String
    }

    LogGroup 'Pull request - Labels' {
        $labels = @()
        $labels += $pull_request.labels.name
        $labels | Format-List | Out-String
    }

    LogGroup 'Calculate release type' {
        $createRelease = $isMerged -and $targetIsDefaultBranch
        $closedPullRequest = $prIsClosed -and -not $isMerged
        $createPrerelease = $labels -Contains 'prerelease' -and -not $createRelease -and -not $closedPullRequest
        $prereleaseName = $prHeadRef -replace '[^a-zA-Z0-9]'

        $ignoreRelease = ($labels | Where-Object { $ignoreLabels -contains $_ }).Count -gt 0
        if ($ignoreRelease) {
            Write-Output 'Ignoring release creation.'
            return
        }

        $majorRelease = ($labels | Where-Object { $majorLabels -contains $_ }).Count -gt 0
        $minorRelease = ($labels | Where-Object { $minorLabels -contains $_ }).Count -gt 0 -and -not $majorRelease
        $patchRelease = (
            ($labels | Where-Object { $patchLabels -contains $_ }
        ).Count -gt 0 -or $autoPatching) -and -not $majorRelease -and -not $minorRelease

        Write-Output '-------------------------------------------------'
        Write-Output "Create a release:               [$createRelease]"
        Write-Output "Create a prerelease:            [$createPrerelease]"
        Write-Output "Create a major release:         [$majorRelease]"
        Write-Output "Create a minor release:         [$minorRelease]"
        Write-Output "Create a patch release:         [$patchRelease]"
        Write-Output "Closed pull request:            [$closedPullRequest]"
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Get latest version - GitHub' {
        $releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Failed to list all releases for the repo.'
            exit $LASTEXITCODE
        }
        $releases | Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table | Out-String

        $latestRelease = $releases | Where-Object { $_.isLatest -eq $true }
        $latestRelease | Format-List | Out-String
        $ghReleaseVersionString = $latestRelease.tagName
        if ($ghReleaseVersionString | IsNotNullOrEmpty) {
            $ghReleaseVersion = New-PSSemVer -Version $ghReleaseVersionString
        } else {
            Write-Warning 'Could not find the latest release version. Using ''0.0.0'' as the version.'
            $ghReleaseVersion = New-PSSemVer -Version '0.0.0'
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'GitHub version:'
        Write-Output ($ghReleaseVersion | Format-Table | Out-String)
        Write-Output $ghReleaseVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Get latest version - PSGallery' {
        try {
            $retryCount = 5
            $retryDelay = 10
            for ($i = 0; $i -lt $retryCount; $i++) {
                try {
                    Write-Output "Finding module [$Name] in the PowerShell Gallery."
                    $latest = Find-PSResource -Name $Name -Repository PSGallery -Verbose:$false
                    Write-Output ($latest | Format-Table | Out-String)
                    break
                } catch {
                    if ($i -eq $retryCount - 1) {
                        throw $_
                    }
                    Write-Warning "Retrying in $retryDelay seconds..."
                    Start-Sleep -Seconds $retryDelay
                }
            }
            $psGalleryVersion = New-PSSemVer -Version $latest.Version
        } catch {
            Write-Warning 'Could not find module online. Using ''0.0.0'' as the version.'
            $psGalleryVersion = New-PSSemVer -Version '0.0.0'
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'PSGallery version:'
        Write-Output ($psGalleryVersion | Format-Table | Out-String)
        Write-Output $psGalleryVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Get latest version - Manifest' {
        Add-PSModulePath -Path (Split-Path -Path $ModulePath -Parent)
        $manifestFilePath = Join-Path $ModulePath "$Name.psd1"
        Write-Output "Module manifest file path: [$manifestFilePath]"
        if (-not (Test-Path -Path $manifestFilePath)) {
            Write-Error "Module manifest file not found at [$manifestFilePath]"
            return
        }
        try {
            $manifestVersion = New-PSSemVer -Version (Test-ModuleManifest $manifestFilePath -Verbose:$false).Version
        } catch {
            if ($manifestVersion | IsNullOrEmpty) {
                Write-Warning 'Could not find the module version in the manifest. Using ''0.0.0'' as the version.'
                $manifestVersion = New-PSSemVer -Version '0.0.0'
            }
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'Manifest version:'
        Write-Output ($manifestVersion | Format-Table | Out-String)
        Write-Output $manifestVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Get latest version' {
        Write-Output "GitHub:    [$($ghReleaseVersion.ToString())]"
        Write-Output "PSGallery: [$($psGalleryVersion.ToString())]"
        Write-Output "Manifest:  [$($manifestVersion.ToString())] (ignored)"
        $latestVersion = New-PSSemVer -Version ($psGalleryVersion, $ghReleaseVersion | Sort-Object -Descending | Select-Object -First 1)
        Write-Output '-------------------------------------------------'
        Write-Output 'Latest version:'
        Write-Output ($latestVersion | Format-Table | Out-String)
        Write-Output $latestVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Calculate new version' {
        # - Increment based on label on PR
        $newVersion = New-PSSemVer -Version $latestVersion
        $newVersion.Prefix = $versionPrefix
        if ($majorRelease) {
            Write-Output 'Incrementing major version.'
            $newVersion.BumpMajor()
        } elseif ($minorRelease) {
            Write-Output 'Incrementing minor version.'
            $newVersion.BumpMinor()
        } elseif ($patchRelease) {
            Write-Output 'Incrementing patch version.'
            $newVersion.BumpPatch()
        } else {
            Write-Output 'Skipping release creation, exiting.'
            return
        }

        Write-Output "Partial new version: [$newVersion]"

        if ($createPrerelease) {
            Write-Output "Adding a prerelease tag to the version using the branch name [$prereleaseName]."
            Write-Output ($releases | Where-Object { $_.tagName -like "*$prereleaseName*" } |
                    Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table -AutoSize | Out-String)

            $newVersion.Prerelease = $prereleaseName
            Write-Output "Partial new version: [$newVersion]"

            if ($datePrereleaseFormat | IsNotNullOrEmpty) {
                Write-Output "Using date-based prerelease: [$datePrereleaseFormat]."
                $newVersion.Prerelease += "$(Get-Date -Format $datePrereleaseFormat)"
                Write-Output "Partial new version: [$newVersion]"
            }

            if ($incrementalPrerelease) {
                # Find the latest prerelease version
                $newVersionString = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"

                # PowerShell Gallery
                $params = @{
                    Name        = $Name
                    Version     = '*'
                    Prerelease  = $true
                    Repository  = 'PSGallery'
                    Verbose     = $false
                    ErrorAction = 'SilentlyContinue'
                }
                Write-Output 'Finding the latest prerelease version in the PowerShell Gallery.'
                Write-Output ($params | Format-Table | Out-String)
                $psGalleryPrereleases = Find-PSResource @params
                $psGalleryPrereleases = $psGalleryPrereleases | Where-Object { $_.Version -like "$newVersionString" }
                $psGalleryPrereleases = $psGalleryPrereleases | Where-Object { $_.Prerelease -like "$prereleaseName*" }
                $latestPSGalleryPrerelease = $psGalleryPrereleases.Prerelease | ForEach-Object {
                    [int]($_ -replace $prereleaseName)
                } | Sort-Object | Select-Object -Last 1
                Write-Output "PSGallery prerelease: [$latestPSGalleryPrerelease]"

                # GitHub
                $ghPrereleases = $releases | Where-Object { $_.tagName -like "*$newVersionString*" }
                $ghPrereleases = $ghPrereleases | Where-Object { $_.tagName -like "*$prereleaseName*" }
                $latestGHPrereleases = $ghPrereleases.tagName | ForEach-Object {
                    $number = $_
                    $number = $number -replace '\.'
                    $number = ($number -split $prereleaseName, 2)[-1]
                    [int]$number
                } | Sort-Object | Select-Object -Last 1
                Write-Output "GitHub prerelease: [$latestGHPrereleases]"

                $latestPrereleaseNumber = [Math]::Max($latestPSGalleryPrerelease, $latestGHPrereleases)
                $latestPrereleaseNumber++
                $latestPrereleaseNumber = ([string]$latestPrereleaseNumber).PadLeft(3, '0')
                $newVersion.Prerelease += $latestPrereleaseNumber
            }
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'New version:'
        Write-Output ($newVersion | Format-Table | Out-String)
        Write-Output $newVersion.ToString()
        Write-Output '-------------------------------------------------'
    }
    Write-Output "New version is [$($newVersion.ToString())]"

    LogGroup 'Update module manifest' {
        Write-Output 'Bump module version -> module metadata: Update-ModuleMetadata'
        $manifestNewVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
        Set-ModuleManifest -Path $manifestFilePath -ModuleVersion $manifestNewVersion -Verbose:$false
        if ($createPrerelease) {
            Write-Output "Prerelease is: [$($newVersion.Prerelease)]"
            Set-ModuleManifest -Path $manifestFilePath -Prerelease $($newVersion.Prerelease) -Verbose:$false
        }

        Show-FileContent -Path $manifestFilePath
    }

    LogGroup 'Install module dependencies' {
        Resolve-PSModuleDependency -ManifestFilePath $manifestFilePath
    }

    if ($createPrerelease -or $createRelease -or $whatIf) {
        LogGroup 'Publish-ToPSGallery' {
            if ($createPrerelease) {
                $publishPSVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)-$($newVersion.Prerelease)"
            } else {
                $publishPSVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
            }
            $psGalleryReleaseLink = "https://www.powershellgallery.com/packages/$Name/$publishPSVersion"
            Write-Output "Publish module to PowerShell Gallery using [$APIKey]"
            if ($whatIf) {
                Write-Output "Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey"
            } else {
                try {
                    Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey
                } catch {
                    Write-Error $_.Exception.Message
                    exit $LASTEXITCODE
                }
            }
            if ($whatIf) {
                Write-Output (
                    "gh pr comment $($pull_request.number) -b 'Published to the" +
                    " PowerShell Gallery [$publishPSVersion]($psGalleryReleaseLink) has been created.'"
                )
            } else {
                Write-GitHubNotice "Module [$Name - $publishPSVersion] published to the PowerShell Gallery."
                gh pr comment $pull_request.number -b "Module [$Name - $publishPSVersion]($psGalleryReleaseLink) published to the PowerShell Gallery."
                if ($LASTEXITCODE -ne 0) {
                    Write-Error 'Failed to comment on the pull request.'
                    exit $LASTEXITCODE
                }
            }
        }

        LogGroup 'New-GitHubRelease' {
            Write-Output 'Create new GitHub release'
            if ($createPrerelease) {
                if ($whatIf) {
                    Write-Output "WhatIf: gh release create $newVersion --title $newVersion --target $prHeadRef --generate-notes --prerelease"
                } else {
                    $releaseURL = gh release create $newVersion --title $newVersion --target $prHeadRef --generate-notes --prerelease
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to create the release [$newVersion]."
                        exit $LASTEXITCODE
                    }
                }
            } else {
                if ($whatIf) {
                    Write-Output "WhatIf: gh release create $newVersion --title $newVersion --generate-notes"
                } else {
                    $releaseURL = gh release create $newVersion --title $newVersion --generate-notes
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to create the release [$newVersion]."
                        exit $LASTEXITCODE
                    }
                }
            }
            if ($whatIf) {
                Write-Output 'WhatIf: gh pr comment $pull_request.number -b "The release [$newVersion] has been created."'
            } else {
                gh pr comment $pull_request.number -b "GitHub release for $Name [$newVersion]($releaseURL) has been created."
                if ($LASTEXITCODE -ne 0) {
                    Write-Error 'Failed to comment on the pull request.'
                    exit $LASTEXITCODE
                }
            }
            Write-GitHubNotice "Release created: [$newVersion]"
        }
    }

    LogGroup 'List prereleases using the same name' {
        $prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$prereleaseName*" }
        $prereleasesToCleanup | Select-Object -Property name, publishedAt, isPrerelease, isLatest | Format-Table | Out-String
    }

    if ((($closedPullRequest -or $createRelease) -and $autoCleanup) -or $whatIf) {
        LogGroup "Cleanup prereleases for [$prereleaseName]" {
            foreach ($rel in $prereleasesToCleanup) {
                $relTagName = $rel.tagName
                Write-Output "Deleting prerelease:            [$relTagName]."
                if ($whatIf) {
                    Write-Output "WhatIf: gh release delete $($rel.tagName) --cleanup-tag --yes"
                } else {
                    gh release delete $rel.tagName --cleanup-tag --yes
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to delete release [$relTagName]."
                        exit $LASTEXITCODE
                    }
                }
            }
        }
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

function Update-PSModuleManifestAliasesToExport {
    <#
    .SYNOPSIS
    Updates the aliases to export in the module manifest.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function',
        Justification = 'Updates a file that is being built.'
    )]
    [CmdletBinding()]
    param(
        # Name of the module.
        [Parameter(Mandatory)]
        [string] $ModuleName,

        # Folder where the module is outputted.
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo] $ModuleOutputFolder
    )
    LogGroup 'Updating aliases to export in module manifest' {
        Write-Host "Module name: [$ModuleName]"
        Write-Host "Module output folder: [$ModuleOutputFolder]"
        $aliases = Get-Command -Module $ModuleName -CommandType Alias
        Write-Host "Found aliases: [$($aliases.Count)]"
        foreach ($alias in $aliases) {
            Write-Host "Alias: [$($alias.Name)]"
        }
        $outputManifestPath = Join-Path -Path $ModuleOutputFolder -ChildPath "$ModuleName.psd1"
        Write-Host "Output manifest path: [$outputManifestPath]"
        Write-Host 'Setting module manifest with AliasesToExport'
        Set-ModuleManifest -Path $outputManifestPath -AliasesToExport $aliases.Name -Verbose
    }
}
