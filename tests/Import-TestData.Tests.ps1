[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$helpersManifestPath = Join-Path -Path $repoRoot -ChildPath 'src/Helpers/Helpers.psd1'
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "Import-TestData-$([guid]::NewGuid())"

$assert = {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$originalTestData = $env:PSMODULE_TEST_DATA
$originalGitHubEnv = $env:GITHUB_ENV

try {
    New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

    Remove-Module -Name Helpers -Force -ErrorAction SilentlyContinue
    Import-Module -Name $helpersManifestPath -Force

    $githubEnvPath = Join-Path -Path $testRoot -ChildPath 'github_env'

    # Secrets and variables are written to GITHUB_ENV, and nothing leaks to the success/pipeline stream.
    Set-Content -Path $githubEnvPath -Value '' -NoNewline
    $env:GITHUB_ENV = $githubEnvPath
    $env:PSMODULE_TEST_DATA = '{"secrets":{"MY_SECRET":"not-a-real-secret"},"variables":{"MY_VARIABLE":"plain-text-value"}}'

    $pipelineOutput = Import-TestData 3> $null 4> $null 5> $null 6> $null

    & $assert ($null -eq $pipelineOutput) 'Import-TestData must not write workflow commands or status messages to the success/pipeline output stream.'

    $envContent = Get-Content -Path $githubEnvPath -Raw
    & $assert ($envContent -match 'MY_SECRET<<') 'Expected the secret to be written to GITHUB_ENV using heredoc syntax.'
    & $assert ($envContent -like '*not-a-real-secret*') 'Expected the secret value to be written to GITHUB_ENV.'
    & $assert ($envContent -match 'MY_VARIABLE<<') 'Expected the variable to be written to GITHUB_ENV using heredoc syntax.'
    & $assert ($envContent -like '*plain-text-value*') 'Expected the variable value to be written to GITHUB_ENV.'

    # The mask command is emitted on the information stream (never the success stream).
    Set-Content -Path $githubEnvPath -Value '' -NoNewline
    $env:PSMODULE_TEST_DATA = '{"secrets":{"MY_SECRET":"not-a-real-secret"}}'
    $information = Import-TestData 6>&1 | Out-String
    & $assert ($information -match '::add-mask::not-a-real-secret') 'Expected the secret value to be masked via ::add-mask:: on the information stream.'

    # A no-op when no test data is provided; nothing on the success/pipeline stream.
    $env:PSMODULE_TEST_DATA = ''
    $noopOutput = Import-TestData 3> $null 4> $null 5> $null 6> $null
    & $assert ($null -eq $noopOutput) 'The no-op path must not emit anything to the success/pipeline output stream.'

    # Missing GITHUB_ENV fails fast with a clear message instead of a generic parameter-binding error.
    $env:PSMODULE_TEST_DATA = '{"variables":{"MY_VARIABLE":"plain-text-value"}}'
    $env:GITHUB_ENV = ''
    $clearError = $false
    try {
        Import-TestData 6> $null
    } catch {
        $clearError = $_.Exception.Message -like '*GITHUB_ENV*'
    }
    & $assert $clearError 'Expected a clear error mentioning GITHUB_ENV when the environment file is not available.'
} finally {
    $env:PSMODULE_TEST_DATA = $originalTestData
    $env:GITHUB_ENV = $originalGitHubEnv
    Remove-Module -Name Helpers -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force
    }
}
