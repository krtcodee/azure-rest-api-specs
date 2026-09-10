# Azure Resilience CLI Generation Configuration

## Repositories and Tools

| Item | Path |
| --- | --- |
| REST API specifications | `C:\azure-rest-api-specs` |
| AAZ specifications | `C:\aaz` |
| Azure CLI | `C:\azure-cli` |
| Azure CLI extensions | `C:\azure-cli-extensions` |
| AAZDev executable | `C:\aaz-venv\Scripts\aaz-dev.exe` |
| Automation script | `.github\skills\azure-resilience-cli-generate\scripts\Invoke-AzureResilienceCliGeneration.ps1` |

Pinned AAZDev version: `4.6.2`.

If the AAZ or Azure CLI extensions repository is missing, the script can clone these public upstream repositories with `-Bootstrap`:

- `https://github.com/Azure/aaz.git`
- `https://github.com/Azure/azure-cli-extensions.git`

Creating a PR additionally requires `gh` authenticated with permission to create a fork and push to it.

A newly cloned AAZ repository must contain the curated `Commands/resilience` tree. If it is not yet available from the upstream default branch, run the skill's Swagger import, endpoint exclusion, root rename, and AAZ export steps first.

## Input

- Swagger module path: `specification/azureresiliencemanagement/resource-manager/Microsoft.AzureResilienceManagement/AzureResilienceManagement`
- Swagger tag: `package-2026-08-31-preview`
- API version: `2026-08-31-preview`
- Resource provider: `Microsoft.AzureResilienceManagement`
- Plane: management plane
- Source: OpenAPI

## Output

- AAZ command root: `resilience`
- AAZ command path: `C:\aaz\Commands\resilience`
- Extension package: `azure-resilience-management`
- Extension path: `C:\azure-cli-extensions\src\azure-resilience-management`
- CLI profile: `latest`

## Resource Selection

Import all operations from the configured API version except the internal LRO polling endpoint:

`/providers/Microsoft.AzureResilienceManagement/locations/{location}/operationStatuses/{operationId}`

The polling endpoint supports generated long-running operations but must not become a user-facing command.

## Intentional Response Contract

The following operations intentionally return an ARM `ErrorResponse`-shaped payload with HTTP `200` to represent partial failure without failing the overall request:

- `RecoveryPlanActions_Finalize`
- `RecoveryJobs_Cancel`
- `RecoveryJobs_Resume`
- `RecoveryJobs_Retry`
- `RecoveryPlanActions_ValidateForOperation`

AAZ must deserialize and expose these successful payloads. Do not replace their success schema with `void` and do not suppress their output.

## AAZDev Interfaces

AAZDev `4.6.2` exposes private localhost interfaces used by its UI, including:

- `POST /AAZ/Editor/Workspaces`
- `POST /AAZ/Editor/Workspaces/{name}/CommandTree/Nodes/aaz/AddSwagger`
- `POST /AAZ/Editor/Workspaces/{name}/CommandTree/Nodes/{path}/Rename`
- `POST /AAZ/Editor/Workspaces/{name}/Generate`
- `POST /CLI/Az/Extension/Modules`
- `PUT /CLI/Az/Extension/Modules/{moduleName}`

These interfaces are not a public compatibility contract. Derive request payloads from the installed pinned package or the running UI, and fail closed if their shape differs.

The bundled script uses the supported `aaz-dev cli regenerate` command after command-model curation. Swagger import, endpoint exclusion, and root rename remain agent-driven because the supported CLI does not expose all three choices.
