#!/bin/bash
#
# Links the Apple-authored agent skills that ship with the selected Xcode into this checkout, so
# Claude Code loads them as the `xcode-integration` plugin (`xcode-integration:translation`,
# `xcode-integration:swiftui-specialist`, …).
#
# Xcode exports its skills as a complete Claude Code plugin under a build-numbered directory
# (`xcrun agent plugin path --plugin-format claude`). This script does not use that directory as-is:
# it builds a skills-only wrapper at .claude/skills/xcode-integration/ holding Xcode's own
# plugin.json plus a symlink to Xcode's skills folder. The exported plugin also carries a .mcp.json
# declaring an `xcode` MCP server; leaving it out keeps this change to skills only, so wiring up
# Xcode's MCP tools stays a separate, deliberate decision.
#
# Why the plugin name matters: several Xcode MCP tools (StringCatalogRead, StringCatalogEdit, …)
# tell the agent to activate `xcode-integration:translation` first. Loose copies in .claude/skills/
# would load unnamespaced and never match.
#
# The wrapper is developer-local (git-ignored) and points into a directory that changes with every
# Xcode build, so re-run this after each Xcode update and in every new worktree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${REPO_ROOT}/.claude/skills/xcode-integration"

# `agent plugin path` materialises the export on first use, so this also works right after an
# Xcode install that has never been launched with the coding assistant.
if ! PLUGIN_PATH="$(xcrun agent plugin path --plugin-format claude 2>/dev/null)" || [ -z "${PLUGIN_PATH}" ]; then
    echo "Skipping: \`xcrun agent plugin path\` is unavailable (Xcode 27 or later required)." >&2
    exit 0
fi

SOURCE_MANIFEST="${PLUGIN_PATH}/.claude-plugin/plugin.json"
SOURCE_SKILLS="${PLUGIN_PATH}/skills"
if [ ! -f "${SOURCE_MANIFEST}" ] || [ ! -d "${SOURCE_SKILLS}" ]; then
    echo "error: ${PLUGIN_PATH} has no .claude-plugin/plugin.json or skills/ folder." >&2
    exit 1
fi

# Always rebuild: a newer Xcode may ship more skills or a different export directory.
rm -rf "${TARGET}"
mkdir -p "${TARGET}/.claude-plugin"
ln -s "${SOURCE_MANIFEST}" "${TARGET}/.claude-plugin/plugin.json"
ln -s "${SOURCE_SKILLS}" "${TARGET}/skills"

SKILLS=()
for skill in "${SOURCE_SKILLS}"/*/; do
    [ -f "${skill}SKILL.md" ] && SKILLS+=("$(basename "${skill}")")
done
echo "Linked ${#SKILLS[@]} Xcode skill(s) as xcode-integration@skills-dir (from ${PLUGIN_PATH})."

# A loose copy of the same skill (e.g. one copied by hand from an earlier Xcode beta) would load a
# second, unnamespaced and likely stale version next to the plugin's.
for name in "${SKILLS[@]}"; do
    if [ -d "${REPO_ROOT}/.claude/skills/${name}" ]; then
        echo "warning: .claude/skills/${name} duplicates xcode-integration:${name}; remove the loose copy." >&2
    fi
done
