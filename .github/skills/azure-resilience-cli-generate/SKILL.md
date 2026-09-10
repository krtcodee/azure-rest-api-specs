---
name: azure-resilience-cli-generate
description: "Generate or refresh the Azure Resilience Management Azure CLI extension from its checked-in Swagger by using AAZDev. Use when asked to generate az resilience commands, regenerate the azure-resilience-management extension, import the Resilience Swagger into AAZ, or prepare the AAZ and CLI extension repositories for pull requests."
argument-hint: "[regenerate|validate|create-pr]"
user-invocable: true
---

# Azure Resilience CLI Generator

Generate the `az resilience` AAZ command models and the
`azure-resilience-management` Azure CLI extension in one agent-run workflow.

## Safety and Contract Rules

- Run only local repository, generation, build, and test operations on the devbox.
- Never run `az login` or any Azure subscription or resource operation. Live testing belongs on the SAW.
- Do not modify TypeSpec or generated OpenAPI as part of CLI generation.
- Preserve the intentional HTTP `200` `ErrorResponse` payloads. The service uses them to report partial failures without failing the overall request.
- Do not hand-edit generated AAZ command files. Put durable CLI customization in the extension's handwritten customization surface.
- Never discard unrelated working-tree changes.
- Do not commit, push, or open pull requests unless explicitly requested.

## Fixed Configuration

Load [configuration.md](./references/configuration.md) before generation. Treat its paths, names, exclusions, and API contract decisions as authoritative.

Use [Invoke-AzureResilienceCliGeneration.ps1](./scripts/Invoke-AzureResilienceCliGeneration.ps1) for deterministic prerequisite checks and extension regeneration. Run it from PowerShell:

```powershell
& .\.github\skills\azure-resilience-cli-generate\scripts\Invoke-AzureResilienceCliGeneration.ps1 -Mode Validate
& .\.github\skills\azure-resilience-cli-generate\scripts\Invoke-AzureResilienceCliGeneration.ps1 -Mode Regenerate
& .\.github\skills\azure-resilience-cli-generate\scripts\Invoke-AzureResilienceCliGeneration.ps1 -Mode CreatePullRequest
```

When `C:\aaz` or `C:\azure-cli-extensions` is absent, add `-Bootstrap` to clone the public Azure repositories. PR creation uses the active `gh` account, creates or reuses that account's fork, commits only the extension package, pushes a feature branch, and opens a PR against `Azure/azure-cli-extensions`.

`-Bootstrap` removes the need to clone `azure-cli-extensions` manually. The AAZ repository must contain `Commands/resilience`; until those command models are merged upstream, create them through this skill's AAZ model-curation steps before regeneration.

The script intentionally does not import Swagger or rename command groups. AAZDev's public CLI cannot preserve both the `resilience` root and the polling-endpoint exclusion. Perform those model-curation steps through the pinned AAZDev UI or localhost APIs, then use the script to regenerate the extension from the curated models.

## Workflow

### 1. Inspect

1. Run the script in `Validate` mode to confirm configured repositories, inputs, curated models, and AAZDev.
2. Report the current branches and scoped working-tree changes in all three repositories.
3. Confirm the configured Swagger and tag exist.
4. Confirm the installed AAZDev version is the pinned version. Stop on a version mismatch because the automation interfaces are private.

### 2. Generate AAZ

1. Start AAZDev locally with the configured CLI, extension, Swagger, and AAZ repository paths.
2. Create a fresh, uniquely named management-plane workspace for `Microsoft.AzureResilienceManagement` from OpenAPI.
3. Import all resources from the configured Swagger tag except the operation-status polling resource listed in the configuration.
4. Rename the generated top-level command group to `resilience`.
5. Export the workspace into the AAZ repository.
6. Verify that `C:\aaz\Commands\resilience` exists and that the operation-status polling endpoint was not exported as a user command.

Prefer AAZDev's localhost APIs when they match the pinned version. If an API payload cannot be derived safely, drive the AAZDev UI with browser automation instead. Do not ask the user to perform UI steps.

### 3. Generate Extension

1. Run the script in `Regenerate` mode. Use `-Force` only after reviewing existing target changes.
2. The script regenerates the complete extension from the curated `resilience` command tree.
3. Preserve handwritten customization files when refreshing an existing extension.
4. Remove generated build residue such as `build`, `dist`, `*.egg-info`, and `__pycache__` from the extension package before reporting PR readiness.

### 4. Complete Package Metadata

Ensure the extension has meaningful `README.md`, `HISTORY.rst`, package metadata, command registration, and focused tests. Do not invent CODEOWNERS identities, minimum CLI versions, or service claims that are not supported by repository evidence.

### 5. Validate

Run all locally available checks:

1. Import and command registration checks.
2. `az resilience --help` using the local development environment.
3. Extension style and lint checks.
4. Focused extension tests; zero collected tests is a failure.
5. Wheel build.
6. A scoped scan confirming that generated success handlers still expose the intentional partial-failure payloads.
7. Scoped `git status` and diff summaries for the AAZ and extension repositories.

Fix generation or package defects and rerun the narrow failing check. Do not change the service contract to make a CLI check pass.

### 6. Create Pull Request

Only when explicitly requested, run the script in `CreatePullRequest` mode:

1. Require an authenticated GitHub CLI session; never request or print a token.
2. Abort when unrelated files are staged in the extensions repository.
3. Validate metadata, focused tests, and wheel creation before committing.
4. Commit only `src/azure-resilience-management`.
5. Push to the active user's fork and open a PR against `Azure/azure-cli-extensions:main`.

## Output

Report:

- Swagger tag and API version used.
- Generated command root and extension package.
- AAZ and extension branches and changed paths.
- Validation checklist with pass or fail status.
- Any check requiring SAW-based live testing.
- Any unresolved metadata that requires an owner decision.
