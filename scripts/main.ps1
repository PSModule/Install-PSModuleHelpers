#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSModulePath = $env:PSModulePath -split [System.IO.Path]::PathSeparator | Select-Object -First 1
Remove-Module -Name Helpers -Force -ErrorAction SilentlyContinue
Get-Command -Module Helpers | ForEach-Object { Remove-Item -Path function:$_ -Force }
Get-Item -Path "$PSModulePath/Helpers/999.0.0" | Remove-Item -Recurse -Force
$modulePath = New-Item -Path "$PSModulePath/Helpers/999.0.0" -ItemType Directory -Force | Select-Object -ExpandProperty FullName
Copy-Item -Path "$PSScriptRoot/Helpers/*" -Destination $modulePath -Recurse -Force
LogGroup 'Importing module' {
    Import-Module -Name Helpers -Verbose
}
