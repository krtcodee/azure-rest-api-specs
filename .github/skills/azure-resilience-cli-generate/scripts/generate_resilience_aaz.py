import argparse
import json
import sys
from pathlib import Path

import aaz_dev


sys.path.insert(0, str(Path(aaz_dev.__file__).resolve().parent))

from command.controller.specs_manager import AAZSpecsManager
from command.controller.workspace_manager import WorkspaceManager
from command.model.configuration import CMDHelp
from swagger.controller.specs_manager import SwaggerSpecsManager
from swagger.utils.source import SourceTypeEnum
from utils.config import Config


EXCLUDED_RESOURCE_ID = (
    "/providers/microsoft.azureresiliencemanagement/locations/{}/operationstatuses/{}"
)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swagger-path", required=True)
    parser.add_argument("--aaz-path", required=True)
    parser.add_argument("--swagger-tag", required=True)
    parser.add_argument("--module", default="azureresiliencemanagement")
    parser.add_argument(
        "--resource-provider", default="Microsoft.AzureResilienceManagement"
    )
    parser.add_argument("--command-root", default="resilience")
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    Config.SWAGGER_PATH = args.swagger_path
    Config.SWAGGER_MODULE_PATH = None
    Config.AAZ_PATH = args.aaz_path
    Config.DEFAULT_SWAGGER_MODULE = args.module
    Config.DEFAULT_RESOURCE_PROVIDER = args.resource_provider

    swagger_specs = SwaggerSpecsManager()
    aaz_specs = AAZSpecsManager()
    module_manager = swagger_specs.get_module_manager(
        Config.DEFAULT_PLANE, Config.DEFAULT_SWAGGER_MODULE
    )
    resource_provider = module_manager.get_openapi_resource_provider(
        Config.DEFAULT_RESOURCE_PROVIDER
    )
    resource_map = resource_provider.get_resource_map_by_tag(args.swagger_tag)
    if not resource_map:
        raise RuntimeError(f"Swagger tag '{args.swagger_tag}' has no resources")

    version_resource_map = {}
    excluded = []
    for resource_id, version_map in resource_map.items():
        if resource_id == EXCLUDED_RESOURCE_ID:
            excluded.append(resource_id)
            continue
        versions = list(version_map)
        if len(versions) != 1:
            raise RuntimeError(
                f"Resource '{resource_id}' has {len(versions)} versions in the tag"
            )
        version_resource_map.setdefault(versions[0], []).append({"id": resource_id})

    if excluded != [EXCLUDED_RESOURCE_ID]:
        raise RuntimeError(
            "The expected operation-status polling resource was not found exactly once"
        )

    workspace = WorkspaceManager.new(
        name="azure-resilience-cli-generation",
        plane=Config.DEFAULT_PLANE,
        folder=WorkspaceManager.IN_MEMORY,
        mod_names=Config.DEFAULT_SWAGGER_MODULE,
        resource_provider=resource_provider.name,
        swagger_manager=swagger_specs,
        aaz_manager=aaz_specs,
        source=SourceTypeEnum.OpenAPI,
    )
    for version, resources in version_resource_map.items():
        workspace.add_new_resources_by_swagger(
            mod_names=Config.DEFAULT_SWAGGER_MODULE,
            version=version,
            resources=resources,
        )

    for node in workspace.iter_command_tree_nodes():
        if not node.help:
            node.help = CMDHelp()
        if not node.help.short:
            node.help.short = f"Manage {node.names[-1]}"

    top_level_groups = list(workspace.ws.command_tree.command_groups.values())
    if len(top_level_groups) != 1:
        names = [group.names for group in top_level_groups]
        raise RuntimeError(
            f"Expected one top-level command group, found {len(names)}: {names}"
        )
    original_names = list(top_level_groups[0].names)
    workspace.rename_command_tree_node(
        *original_names, new_node_names=[args.command_root]
    )

    result = {
        "commandRoot": args.command_root,
        "excludedResources": excluded,
        "resourceCount": sum(len(resources) for resources in version_resource_map.values()),
        "versions": sorted(version_resource_map),
    }
    if not args.validate_only:
        workspace.generate_to_aaz()
        result["exported"] = True
    else:
        result["exported"] = False

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"AAZ generation failed: {error}", file=sys.stderr)
        raise