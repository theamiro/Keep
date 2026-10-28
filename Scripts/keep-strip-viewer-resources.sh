#!/bin/sh
# Removes Runestone's bundled query resources from non-debug sample builds.
set -eu

if [ "${CONFIGURATION:-}" = "Debug" ]; then
    exit 0
fi

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    echo "error: cannot locate built resources to remove viewer bundles"
    exit 1
fi

resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
if [ ! -d "$resources" ]; then
    echo "error: cannot inspect built resources at $resources"
    exit 1
fi

for bundle in \
    "Runestone_Runestone.bundle" \
    "TreeSitterLanguages_TreeSitterJSONQueries.bundle"; do
    artifact="$resources/$bundle"
    if [ -e "$artifact" ] || [ -L "$artifact" ]; then
        rm -rf "$artifact"
    fi
done
