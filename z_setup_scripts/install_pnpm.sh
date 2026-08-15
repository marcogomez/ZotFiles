#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"
source "$SCRIPT_DIR/_config.sh"

install_pnpm() {
  local pnpm_home="$HOME/.local/share/pnpm"

  if [[ -x $pnpm_home/bin/pnpm ]]; then
    print_info "Pnpm is already installed ..."
  else
    print_info "Installing Pnpm ..."

    # The installer always runs `pnpm setup --force`, which appends a PNPM_HOME
    # block to the rc file it infers from $SHELL -- for zsh that is ~/.zshrc, a
    # symlink into this repo, and --force re-appends on every run. There is no
    # opt-out flag, but with SHELL=sh pnpm resolves its target from $ENV, so
    # pointing that at a throwaway file keeps the dotfiles untouched. PATH is
    # handled by dotfiles/zsh/zshrc instead.
    local env_decoy
    env_decoy="$(mktemp)" || handle_error "Failed to create temporary file"

    # The vars belong on the `sh -` side: a prefix on curl would not reach the
    # shell that actually interprets the script.
    curl -fsSL https://get.pnpm.io/install.sh | SHELL=sh ENV="$env_decoy" sh - >/dev/null ||
      handle_error "Failed to install Pnpm"

    rm -f "$env_decoy"

    "$pnpm_home"/bin/pnpm --version >/dev/null 2>&1 ||
      handle_error "Failed to verify Pnpm installation"

    print_success "Pnpm installed successfully."
  fi
}

install_pnpm
