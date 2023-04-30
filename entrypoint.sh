#!/bin/bash
set -euo pipefail

FILE="$(basename "$0")"

# Sanity Check
if [ ! -n "${INPUT_PKG:-}" ]; then
    echo "::error file=$FILE,line=$LINENO::No Package."
    exit 1
fi

##################################################

# Install required packages
pacman -Syu --noconfirm --needed base base-devel git

# ls -l within ubuntu-latest shows owner of clone is runner and group is docker
# id of runner user: uid=1001(runner) gid=123(docker) groups=123(docker),4(adm),101(systemd-journal)
# So lets match that from now on...

# Add docker group
groupadd -g 123 docker

# Add runner user
useradd runner -m -u 1001 -g 123
# When installing dependencies, makepkg will use sudo
# Give user `runner` passwordless sudo access
echo "runner ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers

# Set up sudo cmd to make life a little easier
sudoCMD="sudo -H -u runner"

# Add git config for functionality
${sudoCMD} git config --global --add safe.directory /github/workspace

# Setup paths
refDir="${INPUT_VERSIONDIR:-versions}/${INPUT_REPOTAG:-generic_x86_64}"
refFile="${refDir:-}/${INPUT_PKG:-}"

# Rest doesn't change - its still the file that was used.
echo "refFile=${refFile:-}" >>$GITHUB_OUTPUT

# Get Ref
Ref="${INPUT_PKGREF:-$(${sudoCMD} git -C ${INPUT_PKG:-} rev-parse HEAD)}"

# Assume that if .SRCINFO is missing then it is generated elsewhere.
# AUR checks that .SRCINFO exists so a missing file can't go unnoticed.
# Empty and/or commented lines should be ignored to mitigate false positives.
cd ${INPUT_PKG:-}
if [ -f .SRCINFO ] && ! diff -BI '^\s*#' .SRCINFO <(${sudoCMD} makepkg --printsrcinfo) >/dev/null 2>&1; then
    if [ "${INPUT_UPDATESRCINFO:-false}" == true ]; then
        echo "::warning file=$FILE,line=$LINENO::Mismatched .SRCINFO. Updating with: makepkg --printsrcinfo > .SRCINFO"
        ${sudoCMD} makepkg --printsrcinfo >.SRCINFO
        Ref="${INPUT_PKGREF:-$(${sudoCMD} git rev-parse $(${sudoCMD} git branch --show-current))}"
    else
        echo "::error file=$FILE,line=$LINENO::Mismatched .SRCINFO. Update with: makepkg --printsrcinfo > .SRCINFO"
        exit 1
    fi
fi
cd ../

# Check for version file
if [ ! -f "${refFile:-}" ]; then
    # Ensure required versions directory
    if [ ! -d "${refDir:-}" ]; then
        ${sudoCMD} mkdir -p "${refDir:-}"
    fi

    # Create version file
    ${sudoCMD} touch "${refFile:-}"
    echo "${Ref:-}" >"${refFile:-}"

    # Add version file to tracking
    ${sudoCMD} git add "${refFile:-}"

    echo "requiresUpdate=true" >>$GITHUB_OUTPUT
    exit 0
fi

# File must be there if we made it here.
refFileData=$(cat "${refFile:-}")

# Workout if it needs to be updated.
if [[ "${refFileData:-}" == "${INPUT_PKGREF:-${Ref:-}}" ]]; then
    ${sudoCMD} git add "${refFile:-}"
    echo "requiresUpdate=false" >>$GITHUB_OUTPUT
    exit 0
else
    echo "${INPUT_PKGREF:-${Ref:-}}" >"${refFile:-}"
    ${sudoCMD} git add "${refFile:-}"
    echo "requiresUpdate=true" >>$GITHUB_OUTPUT
    exit 0
fi
