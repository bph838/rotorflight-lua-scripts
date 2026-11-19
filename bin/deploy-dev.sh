#!/usr/bin/env bash
#
# Builds a side-by-side "DEV" copy of the Lua scripts that can live on the
# radio next to an installed release, without overwriting it.
#
#   /SCRIPTS/RF2/            -> /SCRIPTS/RF2DEV/
#   /SCRIPTS/TOOLS/rf2.lua   -> /SCRIPTS/TOOLS/rf2dev.lua   ("Rotorflight 2 DEV")
#   /SCRIPTS/FUNCTIONS/rf2bg -> /SCRIPTS/FUNCTIONS/rf2bgd
#   /WIDGETS/RfTool          -> /WIDGETS/RfToolDv          ("RF Tool DEV")
#   /WIDGETS/RfStats         -> /WIDGETS/RfStatDv          ("RF Stats DEV")
#
# Usage:
#   bin/deploy-dev.sh            # stage only, into tmp/rf2dev
#   bin/deploy-dev.sh E:         # stage, then copy onto the SD card at E:
#
# Note: the release and DEV copies share the global `rf2` table, so avoid
# running a release widget/background function and the DEV tool at the
# same time on the same model.

set -euo pipefail

cd "$(dirname "$0")/.."

STAGE=tmp/rf2dev
DEST=${1:-}

SCRIPT_DIR=RF2DEV
TOOL_FILE=rf2dev.lua
TOOL_NAME="Rotorflight 2 DEV"
BG_FILE=rf2bgd.lua
TOOL_WIDGET=RfToolDv
STATS_WIDGET=RfStatDv

echo "Staging DEV build in ${STAGE}..."
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp -r src/. "${STAGE}/"

# Rename directories and entry-point files.
mv "${STAGE}/SCRIPTS/RF2" "${STAGE}/SCRIPTS/${SCRIPT_DIR}"
mv "${STAGE}/SCRIPTS/TOOLS/rf2.lua" "${STAGE}/SCRIPTS/TOOLS/${TOOL_FILE}"
mv "${STAGE}/SCRIPTS/FUNCTIONS/rf2bg.lua" "${STAGE}/SCRIPTS/FUNCTIONS/${BG_FILE}"
mv "${STAGE}/WIDGETS/RfTool" "${STAGE}/WIDGETS/${TOOL_WIDGET}"
mv "${STAGE}/WIDGETS/RfStats" "${STAGE}/WIDGETS/${STATS_WIDGET}"

# Rewrite hardcoded paths and display names.
find "${STAGE}" -name '*.lua' -type f -print0 | xargs -0 sed -i \
    -e "s#/SCRIPTS/RF2/#/SCRIPTS/${SCRIPT_DIR}/#g" \
    -e "s#\"/SCRIPTS/RF2\"#\"/SCRIPTS/${SCRIPT_DIR}\"#g" \
    -e "s#/WIDGETS/RfTool/#/WIDGETS/${TOOL_WIDGET}/#g" \
    -e "s#/WIDGETS/RfStats/#/WIDGETS/${STATS_WIDGET}/#g"

sed -i "s#TNS|Rotorflight 2|TNE#TNS|${TOOL_NAME}|TNE#" "${STAGE}/SCRIPTS/TOOLS/${TOOL_FILE}"
sed -i 's#^local name = "RF Tool"#local name = "RF Tool DEV"#' "${STAGE}/WIDGETS/${TOOL_WIDGET}/main.lua"
sed -i 's#^local name = "RF Stats"#local name = "RF Stats DEV"#' "${STAGE}/WIDGETS/${STATS_WIDGET}/main.lua"

# Regenerate the compile manifest from the files actually staged.
SCRIPTS="${STAGE}/SCRIPTS/${SCRIPT_DIR}/COMPILE/scripts.lua"
{
    echo 'local scripts = {'
    (cd "${STAGE}" && find . -name '*.lua' -type f ! -path '*/COMPILE/scripts*.lua' | sort) | while read -r FILE; do
        echo "    \"/${FILE#./}\","
    done
    echo '}'
    echo 'return scripts[...]'
} > "${SCRIPTS}"

# Force a recompile on the radio.
echo 'return false' > "${STAGE}/SCRIPTS/${SCRIPT_DIR}/COMPILE/scripts_compiled.lua"

# Sanity check: nothing should still point at the release locations.
if grep -rnE '/SCRIPTS/RF2/|"/SCRIPTS/RF2"|/WIDGETS/RfTool/|/WIDGETS/RfStats/' "${STAGE}" --include='*.lua' \
        | grep -vE '^\S+:[0-9]+:\s*--'; then
    echo "ERROR: release paths remain in the staged files (see above)." >&2
    exit 1
fi

echo "Staged OK."

if [[ -z "${DEST}" ]]; then
    echo "No destination given; copy the contents of ${STAGE} to the SD card root manually."
    exit 0
fi

# Accept Windows drive letters (E: or E:\) as well as POSIX paths.
if command -v cygpath > /dev/null; then
    DEST=$(cygpath -u "${DEST}")
fi

if [[ ! -d "${DEST}/SCRIPTS" ]]; then
    echo "ERROR: ${DEST} does not look like a radio SD card (no SCRIPTS folder)." >&2
    exit 1
fi

echo "Deploying to ${DEST}..."

# Only ever remove the DEV copies; the release install is left untouched.
rm -rf "${DEST}/SCRIPTS/${SCRIPT_DIR}" \
       "${DEST}/WIDGETS/${TOOL_WIDGET}" \
       "${DEST}/WIDGETS/${STATS_WIDGET}"
rm -f  "${DEST}/SCRIPTS/TOOLS/${TOOL_FILE%.lua}.lua"  "${DEST}/SCRIPTS/TOOLS/${TOOL_FILE%.lua}.luac" \
       "${DEST}/SCRIPTS/FUNCTIONS/${BG_FILE%.lua}.lua" "${DEST}/SCRIPTS/FUNCTIONS/${BG_FILE%.lua}.luac"

mkdir -p "${DEST}/SCRIPTS/TOOLS" "${DEST}/SCRIPTS/FUNCTIONS" "${DEST}/WIDGETS"
cp -r "${STAGE}/SCRIPTS/${SCRIPT_DIR}" "${DEST}/SCRIPTS/"
cp "${STAGE}/SCRIPTS/TOOLS/${TOOL_FILE}" "${DEST}/SCRIPTS/TOOLS/"
cp "${STAGE}/SCRIPTS/FUNCTIONS/${BG_FILE}" "${DEST}/SCRIPTS/FUNCTIONS/"
cp -r "${STAGE}/WIDGETS/${TOOL_WIDGET}" "${STAGE}/WIDGETS/${STATS_WIDGET}" "${DEST}/WIDGETS/"

echo "Done. On the radio, open Tools -> \"${TOOL_NAME}\"; it will compile on first launch."
