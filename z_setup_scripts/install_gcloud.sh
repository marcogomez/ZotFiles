#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"
source "$SCRIPT_DIR/_config.sh"

install_gcloud() {
  if gcloud --version >/dev/null 2>&1; then
    print_info "GCloud is already installed ..."
  else
    print_info "Installing GCloud ..."

    sudo apt-get install -y -qq apt-transport-https ca-certificates gnupg ||
      handle_error "Failed to install dependencies"

    # Import the key before adding the repo, so a failed run never leaves an
    # unsigned repo that breaks later apt-get update. (apt-key is gone in modern
    # Ubuntu, so dearmor into the signed-by path.)
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg |
      sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg ||
      handle_error "Failed to add GCloud repository key"

    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" |
      sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null ||
      handle_error "Failed to add GCloud repository"

    sudo apt-get update -qq || handle_error "Failed to update package list"

    sudo apt-get install -y -qq google-cloud-cli || handle_error "Failed to install GCloud"

    print_success "GCloud installed successfully."
  fi
}

install_gcloud
