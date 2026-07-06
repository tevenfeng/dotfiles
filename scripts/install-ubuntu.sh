#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Please run this script as a normal user with sudo privileges, not as root." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required. Please install sudo or run from a sudo-enabled user." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script is intended for Ubuntu/Debian systems with apt-get." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

APT_PACKAGES=(
  net-tools
  zsh
  vim
  git
  build-essential
  curl
  wget
  ripgrep
  tmux
  ca-certificates
  gnupg
)

backup_file() {
  local file="$1"
  if [[ -e "${file}" && ! -L "${file}" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "${file}" "${backup}"
    echo "Backed up ${file} to ${backup}"
  fi
}

install_apt_packages() {
  echo "Installing common apt packages..."
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"
}

install_github_cli() {
  if command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI already installed: $(gh --version | head -n 1)"
    return
  fi

  echo "Installing GitHub CLI from official apt repository..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gh
}

install_oh_my_zsh() {
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    echo "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    echo "Oh My Zsh already installed."
  fi

  local custom_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
  mkdir -p "${custom_dir}/plugins"

  if [[ ! -d "${custom_dir}/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "${custom_dir}/plugins/zsh-autosuggestions"
  else
    git -C "${custom_dir}/plugins/zsh-autosuggestions" pull --ff-only || true
  fi

  if [[ ! -d "${custom_dir}/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${custom_dir}/plugins/zsh-syntax-highlighting"
  else
    git -C "${custom_dir}/plugins/zsh-syntax-highlighting" pull --ff-only || true
  fi

  if [[ ! -f "${HOME}/.zshrc" ]]; then
    cp "${HOME}/.oh-my-zsh/templates/zshrc.zsh-template" "${HOME}/.zshrc"
  fi

  backup_file "${HOME}/.zshrc"
  local zshrc_tmp
  zshrc_tmp="$(mktemp)"
  awk '
    BEGIN { in_plugins = 0; replaced = 0 }
    /^[[:space:]]*plugins=\(/ {
      print "plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
      in_plugins = 1
      replaced = 1
      if ($0 ~ /\)/) {
        in_plugins = 0
      }
      next
    }
    in_plugins {
      if ($0 ~ /\)/) {
        in_plugins = 0
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        print ""
        print "plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
      }
    }
  ' "${HOME}/.zshrc" >"${zshrc_tmp}"
  mv "${zshrc_tmp}" "${HOME}/.zshrc"

  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    echo "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)" || echo "Could not change shell automatically. Run: chsh -s $(command -v zsh)"
  fi
}

install_tmux_config() {
  echo "Applying tmux configuration..."
  backup_file "${HOME}/.tmux.conf"
  cp "${REPO_DIR}/.tmux.conf" "${HOME}/.tmux.conf"

  if [[ ! -d "${HOME}/.tmux/plugins/tpm" ]]; then
    git clone https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm"
  else
    git -C "${HOME}/.tmux/plugins/tpm" pull --ff-only || true
  fi

  echo "Installing tmux plugins via TPM..."
  "${HOME}/.tmux/plugins/tpm/bin/install_plugins" || true
}

main() {
  install_apt_packages
  install_github_cli
  install_oh_my_zsh
  install_tmux_config

  echo
  echo "Done. Restart your terminal, or run: exec zsh"
  echo "For GitHub CLI login, run: gh auth login"
}

main "$@"
