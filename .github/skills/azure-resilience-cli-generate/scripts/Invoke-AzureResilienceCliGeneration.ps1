[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Validate", "Regenerate", "CreatePullRequest")]
    [string] $Mode = "Validate",

    [string] $RestApiSpecsPath = "C:\azure-rest-api-specs",
    [string] $AazPath = "C:\aaz",
    [string] $AzureCliExtensionsPath = "C:\azure-cli-extensions",
    [string] $AazDevPath = "C:\aaz-venv\Scripts\aaz-dev.exe",
    [string] $AazPythonPath = "C:\aaz-venv\Scripts\python.exe",
    [string] $PythonPath = "C:\aaz-venv\Scripts\python.exe",
    [string] $BranchName,
    [string] $CommitMessage = "Add Azure Resilience Management CLI extension",
    [string] $PullRequestTitle = "Add Azure Resilience Management CLI extension",

    [switch] $Bootstrap,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$expectedAazDevVersion = "4.6.2"
$aazRepositoryUrl = "https://github.com/Azure/aaz.git"
$cliExtensionsRepositoryUrl = "https://github.com/Azure/azure-cli-extensions.git"
$cliExtensionsUpstreamRepository = "Azure/azure-cli-extensions"
$swaggerModuleRelativePath = "specification\azureresiliencemanagement\resource-manager\Microsoft.AzureResilienceManagement\AzureResilienceManagement"
$swaggerTag = "package-2026-08-31-preview"
$apiVersion = "2026-08-31-preview"
$commandRoot = "resilience"
$extensionName = "azure-resilience-management"
$excludedCommandPattern = "operation[- ]?statuses?"
$partialFailureOperationIds = @(
    "RecoveryPlanActions_Finalize",
    "RecoveryJobs_Cancel",
    "RecoveryJobs_Resume",
    "RecoveryJobs_Retry",
    "RecoveryPlanActions_ValidateForOperation"
)

function Assert-Path {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description was not found at '$Path'."
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git -C '$Repository' $($Arguments -join ' ') failed:`n$output"
    }

    return $output
}

function Initialize-Repository {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $RepositoryUrl,

        [Parameter(Mandatory)]
        [string] $Description
    )

    if (Test-Path -LiteralPath $Path) {
        return
    }
    if (-not $Bootstrap) {
        throw "$Description is not cloned at '$Path'. Rerun with -Bootstrap to clone it."
    }

    $parent = Split-Path -Parent $Path
    if ($PSCmdlet.ShouldProcess($Path, "Clone $RepositoryUrl")) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        & git clone --filter=blob:none $RepositoryUrl $Path
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone $RepositoryUrl into '$Path'."
        }
    }
}

function Invoke-PackageValidation {
    param(
        [Parameter(Mandatory)]
        [string] $PackagePath
    )

    Push-Location $PackagePath
    try {
        & $PythonPath setup.py check
        if ($LASTEXITCODE -ne 0) {
            throw "Package metadata validation failed."
        }

        & $PythonPath setup.py bdist_wheel
        if ($LASTEXITCODE -ne 0) {
            throw "Wheel build failed."
        }

        & $PythonPath -c "import pytest" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "pytest is unavailable. Install the extension development dependencies before creating a PR."
        }

        & $PythonPath -m pytest azext_azure_resilience_management/tests/latest
        if ($LASTEXITCODE -ne 0) {
            throw "Focused extension tests failed."
        }
    }
    finally {
        Pop-Location
        Get-ChildItem -LiteralPath $PackagePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @("build", "dist") -or $_.Name -like "*.egg-info" } |
            Remove-Item -Recurse -Force
    }
}

Initialize-Repository -Path $AazPath -RepositoryUrl $aazRepositoryUrl -Description "AAZ repository"
Initialize-Repository -Path $AzureCliExtensionsPath -RepositoryUrl $cliExtensionsRepositoryUrl -Description "Azure CLI extensions repository"

$swaggerModulePath = Join-Path $RestApiSpecsPath $swaggerModuleRelativePath
$readmePath = Join-Path $swaggerModulePath "readme.md"
$openApiPath = Join-Path $swaggerModulePath "preview\$apiVersion\openapi.json"
$aazCommandPath = Join-Path $AazPath "Commands\$commandRoot"
$extensionPath = Join-Path $AzureCliExtensionsPath "src\$extensionName"

$requiredPaths = @(
    @{ Path = $RestApiSpecsPath; Description = "REST API specifications repository" },
    @{ Path = $AazPath; Description = "AAZ repository" },
    @{ Path = $AzureCliExtensionsPath; Description = "Azure CLI extensions repository" },
    @{ Path = $AazDevPath; Description = "AAZDev executable" },
    @{ Path = $AazPythonPath; Description = "AAZDev Python executable" },
    @{ Path = $readmePath; Description = "Swagger readme" },
    @{ Path = $openApiPath; Description = "Generated OpenAPI document" },
    @{ Path = $aazCommandPath; Description = "Curated AAZ command root" },
    @{ Path = $extensionPath; Description = "Azure CLI extension package" }
)

foreach ($requiredPath in $requiredPaths) {
    Assert-Path @requiredPath
}

$installedVersion = & $AazPythonPath -c "import importlib.metadata as m; print(m.version('aaz-dev'))"
if ($LASTEXITCODE -ne 0) {
    throw "Could not determine the installed AAZDev version."
}
$installedVersion = $installedVersion.Trim()
if ($installedVersion -ne $expectedAazDevVersion) {
    throw "AAZDev version '$installedVersion' is installed; version '$expectedAazDevVersion' is required."
}

$readmeContent = Get-Content -LiteralPath $readmePath -Raw
if ($readmeContent -notmatch [regex]::Escape("tag: $swaggerTag")) {
    throw "Swagger tag '$swaggerTag' was not found in '$readmePath'."
}
if ($readmeContent -notmatch [regex]::Escape("preview/$apiVersion/openapi.json")) {
    throw "API version '$apiVersion' is not an input of '$swaggerTag'."
}

$excludedCommands = Get-ChildItem -LiteralPath $aazCommandPath -Recurse -ErrorAction Stop |
    Where-Object { $_.Name -match $excludedCommandPattern }
if ($excludedCommands) {
    throw "The curated AAZ command tree appears to expose the excluded operation-status polling endpoint."
}

$openApiContent = Get-Content -LiteralPath $openApiPath -Raw
foreach ($operationId in $partialFailureOperationIds) {
    if ($openApiContent -notmatch [regex]::Escape('"operationId": "' + $operationId + '"')) {
        throw "Intentional partial-failure operation '$operationId' was not found in the configured OpenAPI document."
    }
}

Write-Host "Validated AAZDev $installedVersion, Swagger tag $swaggerTag, API version $apiVersion, and command root '$commandRoot'."

$stagedFiles = @()
if ($Mode -eq "CreatePullRequest") {
    $stagedFiles = @(Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("diff", "--cached", "--name-only"))
    $unrelatedStagedFiles = @($stagedFiles | Where-Object { $_ -and $_ -notlike "src/$extensionName/*" })
    if ($unrelatedStagedFiles.Count -gt 0) {
        throw "Unrelated files are already staged in the CLI extensions repository:`n$($unrelatedStagedFiles -join "`n")"
    }
}

$shouldRegenerate = $Mode -in @("Regenerate", "CreatePullRequest")
if ($shouldRegenerate) {
    $aazStatus = @(Invoke-Git -Repository $AazPath -Arguments @("status", "--short", "--", "Commands/$commandRoot", "Commands/readme.md"))
    $extensionStatus = @(Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("status", "--short", "--", "src/$extensionName"))
    if (-not $Force -and ($aazStatus.Count -gt 0 -or $extensionStatus.Count -gt 0)) {
        throw "Generation targets contain local changes. Review them first or rerun with -Force to regenerate deliberately."
    }

    $arguments = @(
        "cli",
        "regenerate",
        "--aaz-path", $AazPath,
        "--cli-extension-path", $AzureCliExtensionsPath,
        "--extension-or-module-name", $extensionName
    )

    if ($PSCmdlet.ShouldProcess($extensionPath, "Regenerate '$extensionName' from curated AAZ command models")) {
        & $AazDevPath @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "AAZDev extension regeneration failed with exit code $LASTEXITCODE."
        }
    }

    if (-not $WhatIfPreference) {
        Invoke-PackageValidation -PackagePath $extensionPath
    }
}

if ($Mode -eq "CreatePullRequest") {
    if ($WhatIfPreference) {
        Write-Host "WhatIf: would create a feature branch, commit only src/$extensionName, push to the active GitHub user's fork, and open a PR against $cliExtensionsUpstreamRepository."
    }
    else {
        & gh auth status --hostname github.com *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub CLI is not authenticated. Run 'gh auth login' directly in the terminal, then retry."
        }

        $githubUser = (& gh api user --jq .login).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $githubUser) {
            throw "Could not determine the active GitHub user."
        }

        if (-not $BranchName) {
            $currentBranch = (Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("branch", "--show-current")).Trim()
            $BranchName = if ($currentBranch -and $currentBranch -ne "main") {
                $currentBranch
            }
            else {
                "feature-azure-resilience-management-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
            }
        }

        $currentBranch = (Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("branch", "--show-current")).Trim()
        if ($currentBranch -eq "main") {
            Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("switch", "-c", $BranchName) | Out-Null
        }
        elseif ($currentBranch -ne $BranchName) {
            throw "The repository is on branch '$currentBranch', but PR branch '$BranchName' was requested. Switch branches or omit -BranchName."
        }

        & gh repo fork $cliExtensionsUpstreamRepository --clone=false *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create or locate the GitHub fork for $cliExtensionsUpstreamRepository."
        }

        $forkRemoteName = "automation-fork"
        $forkUrl = "https://github.com/$githubUser/azure-cli-extensions.git"
        $remoteNames = @(Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("remote"))
        if ($forkRemoteName -in $remoteNames) {
            Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("remote", "set-url", $forkRemoteName, $forkUrl) | Out-Null
        }
        else {
            Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("remote", "add", $forkRemoteName, $forkUrl) | Out-Null
        }

        Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("add", "--", "src/$extensionName") | Out-Null
        $filesToCommit = @(Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("diff", "--cached", "--name-only", "--", "src/$extensionName"))
        if ($filesToCommit.Count -eq 0) {
            throw "No extension changes were produced; there is nothing to commit or submit."
        }

        Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("commit", "-m", $CommitMessage, "--", "src/$extensionName") | Out-Null
        Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("push", "--set-upstream", $forkRemoteName, $BranchName) | Out-Null

        $pullRequestBody = @"
Generates the Azure Resilience Management CLI extension from the curated AAZ command models.

- Command root: ``az resilience``
- API version: ``$apiVersion``
- Swagger tag: ``$swaggerTag``
"@
        & gh pr create --repo $cliExtensionsUpstreamRepository --base main --head "${githubUser}:$BranchName" --title $PullRequestTitle --body $pullRequestBody
        if ($LASTEXITCODE -ne 0) {
            throw "The commit was pushed, but GitHub PR creation failed."
        }
    }
}

$finalAazStatus = Invoke-Git -Repository $AazPath -Arguments @("status", "--short", "--", "Commands/$commandRoot", "Commands/readme.md")
$finalExtensionStatus = Invoke-Git -Repository $AzureCliExtensionsPath -Arguments @("status", "--short", "--", "src/$extensionName")

Write-Host "AAZ target status:"
$finalAazStatus | ForEach-Object { Write-Host $_ }
Write-Host "Extension target status:"
$finalExtensionStatus | ForEach-Object { Write-Host $_ }
