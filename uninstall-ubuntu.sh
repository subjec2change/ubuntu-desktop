#!/bin/bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
BRAVE_KEYRING_PATH="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
BRAVE_SOURCES_PATH="/etc/apt/sources.list.d/brave-browser-release.sources"

delete_script_prompt() {
    read -r -p "Do you want to delete the downloaded script file (${SCRIPT_NAME})? (y/n): " delete_file
    if [[ "$delete_file" == "y" ]]; then
        local script_path
        script_path="$(realpath "$0")"
        rm -- "$script_path"
        echo "Script file deleted."
    else
        echo "Script file retained."
    fi
}

require_ubuntu() {
    if [[ ! -r /etc/os-release ]]; then
        echo "Unable to detect the operating system. This script supports Ubuntu."
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        echo "This script supports Ubuntu only."
        exit 1
    fi
}

require_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is required to run this script."
        exit 1
    fi

    sudo -v
}

ensure_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command not found: $command_name"
        exit 1
    fi
}

echo "************************************************************"
echo "* DISCLAIMER:                                              *"
echo "* This script removes the desktop environment configured   *"
echo "* by the companion installer and is provided AS-IS.        *"
echo "* Review it carefully and proceed at your own risk.        *"
echo "************************************************************"

read -r -p "Do you agree to proceed? (y/n): " agreement

if [[ "$agreement" != "y" ]]; then
    echo "You have declined the agreement. Exiting script."
    delete_script_prompt
    exit 1
fi

echo "Proceeding with the uninstallation..."

require_ubuntu
require_sudo
ensure_command systemctl
ensure_command realpath

if systemctl list-unit-files xrdp.service >/dev/null 2>&1; then
    echo "Stopping XRDP service..."
    sudo systemctl stop xrdp || true
    sudo systemctl disable xrdp || true
fi

echo "Removing XRDP, XFCE, Brave Browser, and related packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y \
    xrdp \
    xfce4 \
    xfce4-goodies \
    brave-browser \
    gdebi

if [[ -f "$BRAVE_SOURCES_PATH" ]]; then
    echo "Removing Brave Browser repository configuration..."
    sudo rm -f "$BRAVE_SOURCES_PATH"
fi

if [[ -f "$BRAVE_KEYRING_PATH" ]]; then
    echo "Removing Brave Browser signing key..."
    sudo rm -f "$BRAVE_KEYRING_PATH"
fi

echo "Removing the default XFCE session configuration for newly created users..."
sudo rm -f /etc/skel/.xsession

read -r -p "Enter the RDP username to remove (leave blank to keep the user): " remove_user
if [[ -n "$remove_user" ]]; then
    if id "$remove_user" >/dev/null 2>&1; then
        echo "Deleting user: $remove_user"
        sudo deluser --remove-home "$remove_user"
    else
        echo "User '$remove_user' does not exist. Skipping user removal."
    fi
fi

echo "Disabling GUI startup..."
sudo systemctl set-default multi-user.target

echo "Cleaning up unneeded dependencies..."
sudo apt-get autoremove -y
sudo apt-get clean

echo "Uninstallation complete."

delete_script_prompt

read -r -p "Do you want to reboot now? (y/N): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    sudo reboot
else
    echo "Reboot skipped. You may need to manually reboot for changes to take effect."
fi
