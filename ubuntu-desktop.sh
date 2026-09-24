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

configure_firewall() {
    echo "Configuring firewall access for RDP..."
    sudo ufw allow 3389/tcp

    if sudo ufw status | grep -q "^Status: active"; then
        echo "UFW is active and now allows TCP port 3389."
    else
        echo "UFW is installed but not enabled. Port 3389 has been added to the rules."
        echo "Enable UFW manually after confirming your current SSH/network rules are safe."
    fi
}

configure_brave_repository() {
    echo "Configuring the Brave Browser repository..."
    sudo curl -fsSLo "$BRAVE_KEYRING_PATH" \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    sudo curl -fsSLo "$BRAVE_SOURCES_PATH" \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-release.sources
}

echo "************************************************************"
echo "* DISCLAIMER:                                              *"
echo "* This script configures an Ubuntu desktop environment     *"
echo "* and is provided AS-IS without warranties or guarantees.  *"
echo "* Review it before use and proceed at your own risk.       *"
echo "************************************************************"

read -r -p "Do you agree to proceed? (y/n): " agreement

if [[ "$agreement" != "y" ]]; then
    echo "You have declined the agreement. Exiting script."
    echo "Installation aborted. You can rerun the script anytime to proceed."
    delete_script_prompt
    exit 1
fi

echo "Proceeding with the setup..."

require_ubuntu
require_sudo
ensure_command systemctl
ensure_command useradd
ensure_command chpasswd
ensure_command realpath

echo "Updating package metadata and upgrading installed packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "Installing desktop, remote access, and integration packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xfce4 \
    xfce4-goodies \
    xrdp \
    ufw \
    gdebi \
    xdg-utils \
    curl \
    ca-certificates \
    apt-transport-https

echo "Configuring XRDP to use XFCE for new users..."
printf 'startxfce4\n' | sudo tee /etc/skel/.xsession >/dev/null

echo "Enabling and starting XRDP..."
sudo systemctl enable xrdp
sudo systemctl restart xrdp

configure_firewall

echo "Creating a new user for RDP login..."
read -r -p "Enter a new username for RDP: " new_user

if [[ -z "$new_user" ]]; then
    echo "Username cannot be empty."
    exit 1
fi

if [[ ! "$new_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    echo "Username contains unsupported characters."
    exit 1
fi

if id "$new_user" >/dev/null 2>&1; then
    echo "The user '$new_user' already exists. Choose a different username."
    exit 1
fi

sudo useradd -m -s /bin/bash "$new_user"

while true; do
    read -r -s -p "Enter a password for $new_user: " password
    echo
    read -r -s -p "Retype the password: " password_confirm
    echo

    if [[ -z "$password" ]]; then
        echo "Password cannot be empty."
        continue
    fi

    if [[ "$password" == "$password_confirm" ]]; then
        printf '%s:%s\n' "$new_user" "$password" | sudo chpasswd
        break
    fi

    echo "Passwords do not match. Please try again."
done

echo "Granting the new user sudo privileges..."
sudo usermod -aG sudo "$new_user"

echo "Configuring XFCE as the session for $new_user..."
printf 'startxfce4\n' | sudo tee "/home/$new_user/.xsession" >/dev/null
sudo chown "$new_user:$new_user" "/home/$new_user/.xsession"

configure_brave_repository

echo "Installing Brave Browser..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y brave-browser

echo "Setting GDebi as the default application for .deb files..."
sudo -u "$new_user" xdg-mime default gdebi.desktop application/vnd.debian.binary-package || true

echo "Restarting XRDP service..."
sudo systemctl restart xrdp

echo "Installation complete. You can now connect via RDP."
echo "Use the following credentials:"
echo "Username: $new_user"
echo "Password: (You set this during installation)"
echo "RDP Address: Use your server IP address."

delete_script_prompt
