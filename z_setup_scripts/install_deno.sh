#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"
source "$SCRIPT_DIR/_config.sh"

install_deno() {
  if [[ -x $HOME/.deno/bin/deno ]]; then
    print_info "Deno is already installed ..."
  else
    print_info "Installing Deno ..."

    # The installer hard-fails without unzip (or 7z).
    command -v unzip >/dev/null 2>&1 || install_with_package_manager "unzip"

    # CI=1 skips the installer's shell-setup step, which would otherwise prompt
    # interactively and append PATH/completion lines to ~/.zshrc -- a symlink
    # into this repo. PATH is handled by dotfiles/zsh/zshrc instead.
    CI=1 curl -fsSL https://deno.land/install.sh | sh -s -- --no-modify-path >/dev/null ||
      handle_error "Failed to install Deno"

    "$HOME"/.deno/bin/deno --version >/dev/null 2>&1 ||
      handle_error "Failed to verify Deno installation"

    print_success "Deno installed successfully."
  fi
}

install_deno
