#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"
source "$SCRIPT_DIR/_config.sh"

install_neovim() {
  print_info "Resolving latest stable Neovim ..."

  # Ask GitHub for the latest *stable* (non-prerelease) Neovim release.
  local latest_tag latest_ver installed_ver
  latest_tag="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null |
    grep -Po '"tag_name":\s*"\K[^"]+')"
  [ -n "$latest_tag" ] || handle_error "Failed to determine the latest stable Neovim version"
  latest_ver="${latest_tag#v}"

  # What, if anything, is installed right now (source-built or from apt)?
  installed_ver="$(nvim --version 2>/dev/null | head -1 | grep -Po 'NVIM v\K[0-9]+\.[0-9]+\.[0-9]+')"

  # Already at (or ahead of) the latest stable? Nothing to do.
  if [ -n "$installed_ver" ] && dpkg --compare-versions "$installed_ver" ge "$latest_ver"; then
    print_info "Neovim v$installed_ver is already >= latest stable v$latest_ver ..."
    return 0
  fi

  if [ -n "$installed_ver" ]; then
    print_info "Neovim v$installed_ver is older than latest stable v$latest_ver — replacing ..."
  else
    print_info "No Neovim installed — building latest stable v$latest_ver ..."
  fi

  # Remove any existing Neovim first (a previously source-built package or the
  # distro's neovim / neovim-runtime split) so the freshly built package can't
  # collide on shared files like /usr/share/applications/nvim.desktop.
  sudo apt-get remove --purge -y -qq neovim neovim-runtime >/dev/null 2>&1 || true
  sudo rm -f /usr/share/applications/nvim.desktop
  sudo apt-get autoremove -y -qq >/dev/null 2>&1 || true

  cd "$DOTDIR" || handle_error "Failed to change directory to $DOTDIR"

  rm -rf neovim || handle_error "Failed to remove Neovim source directory"

  git clone --quiet https://github.com/neovim/neovim ||
    handle_error "Failed to clone repository"

  cd neovim || handle_error "Failed to enter Neovim directory"

  git fetch --tags --quiet || handle_error "Failed to fetch tags"

  git checkout "$latest_tag" -q ||
    handle_error "Failed to checkout $latest_tag"

  make CMAKE_BUILD_TYPE=RelWithDebInfo -j"$(nproc)" ||
    handle_error "Failed to build Neovim"

  cd build || handle_error "Failed to enter build directory"

  cpack -G DEB || handle_error "Failed to create Neovim package"

  local nvim_deb
  nvim_deb="$(find . -maxdepth 1 -name '*.deb' | head -1)"
  [ -n "$nvim_deb" ] || handle_error "cpack produced no .deb package"

  sudo dpkg -i --force-all "$nvim_deb" ||
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y -qq ||
    handle_error "Failed to install Neovim package"

  cd "$DOTDIR" || handle_error "Failed to return to $DOTDIR"

  print_success "Neovim v$latest_ver installed successfully."
}

install_neovim
