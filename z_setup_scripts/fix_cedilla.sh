#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"
source "$SCRIPT_DIR/_config.sh"

fix_cedilla() {
  print_info "Fixing cedilla character on XCompose ..."

  mkdir -p "$DOTDIR"/dotfiles/x || handle_error "Failed to create directory: $DOTDIR/dotfiles/x"

  sed -e 's,\xc4\x86,\xc3\x87,g' -e 's,\xc4\x87,\xc3\xa7,g' \
    </usr/share/X11/locale/en_US.UTF-8/Compose \
    >"$DOTDIR"/dotfiles/x/XCompose || handle_error "Failed to fix cedilla character"

  link_file "${DOTDIR}/dotfiles/x/XCompose" "${HOME}/.XCompose"

  # Add the 'en' locale to the cedilla immodule for whichever GTK immodules
  # caches exist (GTK2's is absent on newer systems). Back up once, patch idempotently.
  for imcache in \
    /usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache \
    /usr/lib/x86_64-linux-gnu/gtk-2.0/2.10.0/immodules.cache; do
    if [ -f "$imcache" ]; then
      [ -f "$imcache.bckp" ] || sudo cp "$imcache" "$imcache.bckp"
      sudo sed -i 's,"az:ca:co:fr:gv:oc:pt:sq:tr:wa","az:ca:co:fr:gv:oc:pt:sq:tr:wa:en",g' "$imcache"
    else
      print_warning "Skipping cedilla patch: $imcache not present"
    fi
  done

  sudo cp "$DOTDIR"/dotfiles/etc/environment /etc/environment
}

fix_cedilla

