#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"
source "$SCRIPT_DIR/_config.sh"

install_bun() {
  if [[ -x $HOME/.bun/bin/bun ]]; then
    print_info "Bun is already installed ..."
  else
    print_info "Installing Bun ..."

    # The installer hard-fails without unzip.
    command -v unzip >/dev/null 2>&1 || install_with_package_manager "unzip"

    # The installer drops the binary first, then appends PATH lines to ~/.zshrc
    # -- a symlink into this repo -- unless `command -v bun` already resolves,
    # in which case it just installs completions and exits. Pre-seeding PATH
    # with the install dir takes that exit and leaves the dotfiles alone.
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    curl -fsSL https://bun.sh/install | bash >/dev/null ||
      handle_error "Failed to install Bun"

    "$BUN_INSTALL"/bin/bun --version >/dev/null 2>&1 ||
      handle_error "Failed to verify Bun installation"

    # The installer pipes `bun completions` to /dev/null when non-interactive,
    # so write the file dotfiles/zsh/zshrc sources ourselves. SHELL is forced
    # because bun picks the completion dialect from it.
    SHELL=zsh "$BUN_INSTALL"/bin/bun completions >"$BUN_INSTALL/_bun" ||
      handle_error "Failed to generate Bun completions"

    print_success "Bun installed successfully."
  fi
}

install_bun
