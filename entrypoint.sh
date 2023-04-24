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
pacman -Syu --noconfirm --needed sudo git

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

# Setup versions directory
if [ ! -d "${INPUT_VERSIONDIR:-versions}" ]; then
    ${sudoCMD} mkdir -p "${refDir:-}"
    ${sudoCMD} touch "${refFile:-}"
    echo "${INPUT_PKGREF:-$(${sudoCMD} git -C ${INPUT_PKG:-} rev-parse HEAD)}" >"${refFile:-}"
    ${sudoCMD} git add "${refFile:-}"
    echo "requiresUpdate=true" >>$GITHUB_OUTPUT
    exit 0
else
    if [ ! -d "${refDir:-}" ]; then
        ${sudoCMD} mkdir -p "${refDir:-}"
        ${sudoCMD} touch "${refFile:-}"
        echo "${INPUT_PKGREF:-$(${sudoCMD} git -C ${INPUT_PKG:-} rev-parse HEAD)}" >"${refFile:-}"
        ${sudoCMD} git add "${refFile:-}"
        echo "requiresUpdate=true" >>$GITHUB_OUTPUT
        exit 0
    else
        if [ ! -f "${refFile:-}" ]; then
            ${sudoCMD} touch "${refFile:-}"
            echo "${INPUT_PKGREF:-$(${sudoCMD} git -C ${INPUT_PKG:-} rev-parse HEAD)}" >"${refFile:-}"
            ${sudoCMD} git add "${refFile:-}"
            echo "requiresUpdate=true" >>$GITHUB_OUTPUT
            exit 0
        fi
    fi
fi

# File must be there if we made it.
refFileData=$(cat "${refFile:-}")

# Workout if it needs to be updated.
if [[ "${refFileData:-}" == "${INPUT_PKGREF:-$(${sudoCMD} git -C ${INPUT_PKG:-} rev-parse HEAD)}" ]]; then
    ${sudoCMD} git add "${refFile:-}"
    echo "requiresUpdate=false" >>$GITHUB_OUTPUT
    exit 0
else
    echo "${INPUT_PKGREF:-$(${sudoCMD} git -C ${INPUT_PKG:-} rev-parse HEAD)}" >"${refFile:-}"
    ${sudoCMD} git add "${refFile:-}"
    exit "requiresUpdate=true" >>$GITHUB_OUTPUT
    exit 0
fi
