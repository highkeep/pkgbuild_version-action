#!/bin/bash
set -euo pipefail

FILE="$(basename "$0")"

# Sanity Check
#[ -n "${INPUT_PKG:-}" ] || echo "::error file=$FILE,line=$LINENO"::No Package. && exit 1
echo "${INPUT_PKG:-}"

##################################################

# Install required packages
pacman -Syu --noconfirm --needed sudo git openssh

# Added builder as seen in edlanglois/pkgbuild-action - mainly for permissions
useradd builder -m
# When installing dependencies, makepkg will use sudo
# Give user `builder` passwordless sudo access
echo "builder ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers

# Give all users (particularly builder) full access to these files
chmod -R a+rw .

# Set up sudo cmd to make life a little easier
sudoCMD="sudo -H -u builder"

# Add git config for functionality
${sudoCMD} mkdir /home/builder/.ssh && ${sudoCMD} ssh-keyscan github.com >>/home/builder/.ssh/known_hosts
${sudoCMD} git remote set-url origin https://x-access-token:${INPUT_TOKEN}@github.com/${INPUT_GHREPO}
${sudoCMD} git config --global --add safe.directory $(pwd)
${sudoCMD} git config --global user.name 'Version Action'
${sudoCMD} git config --global user.email 'builder@users.noreply.github.com'

# Sync data function
function sync() {
    ${sudoCMD} git fetch --quiet
    if [[ "$(git rev-parse origin/$GITHUB_BASE_REF)" != "$(git rev-parse HEAD)" ]]; then
        ${sudoCMD} git pull --quiet
    fi
}

# Setup paths
refDir="${INPUT_VERSIONDIR:-versions}/${INPUT_REPOTAG:-generic_x86_64}"
refFile="${refDir:-}/${INPUT_PKG:-}"

# Run sync
sync

# Setup versions directory
if [ ! -d "${INPUT_VERSIONDIR:-versions}" ]; then
    ${sudoCMD} mkdir -p "${refDir:-}"
    ${sudoCMD} touch "${refFile:-}"
    git add "${refFile:-}"
    echo "updatePkg=true" >>$GITHUB_OUTPUT
    sync && exit 0
else
    if [ ! -d "${refDir:-}" ]; then
        ${sudoCMD} mkdir -p "${refDir:-}"
        ${sudoCMD} touch "${refFile:-}"
        git add "${refFile:-}"
        echo "updatePkg=true" >>$GITHUB_OUTPUT
        sync && exit 0
    else
        if [ ! -f "${refFile:-}" ]; then
            ${sudoCMD} touch "${refFile:-}"
            git add "${refFile:-}"
            echo "updatePkg=true" >>$GITHUB_OUTPUT
            sync && exit 0
        fi
    fi
fi

# File must be there if we made it.
refFileData=$(cat "${refFile:-}")

# Workout if it needs to be updated.
if [[ "${refFileData:-}" == "${INPUT_PKGREF:-$(git -C ${INPUT_PKG:-} rev-parse HEAD)}" ]]; then
    echo "updatePkg=false" >>$GITHUB_OUTPUT
    sync && exit 0
else
    echo "${INPUT_PKGREF:-$(git -C ${INPUT_PKG:-} rev-parse HEAD)}" >"${refFile:-}"
    exit "updatePkg=true" >>$GITHUB_OUTPUT
    sync && exit 0
fi
