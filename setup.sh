#!/bin/bash

source "$(dirname "$0")/z_setup_scripts/_helpers.sh"
source "$(dirname "$0")/z_setup_scripts/_config.sh"

update_system() {
  print_info "Updating system ..."

  if [ -f /etc/apt/sources.list.d/dvd.list ]; then
    print_info "Removing DVD source ..."
    sudo mv /etc/apt/sources.list.d/dvd.list /etc/apt/sources.list.d/dvd.list.bak
  fi

  sudo dpkg --add-architecture i386 || handle_error "Failed to add i386 architecture."

  # A prior aborted run can leave a third-party repo list whose signing key is
  # missing, or is a keybox database (apt only accepts a plain exported key in
  # signed-by). Either breaks apt-get update. Drop the orphan; the recipe that
  # owns it re-adds it cleanly later.
  for repo_list in /etc/apt/sources.list.d/*.list; do
    [ -e "$repo_list" ] || continue
    repo_key="$(grep -hoP 'signed-by=\K[^] ]+' "$repo_list" 2>/dev/null | head -1)"
    [ -n "$repo_key" ] || continue
    keybox=""
    file "$repo_key" 2>/dev/null | grep -qi 'keybox' && keybox="yes"
    if [ ! -e "$repo_key" ] || [ -n "$keybox" ]; then
      print_warning "Removing orphan/invalid repo $(basename "$repo_list") (key: $repo_key)"
      sudo rm -f "$repo_list"
      [ -n "$keybox" ] && sudo rm -f "$repo_key"
    fi
  done

  sudo apt-get update -qq || handle_error "Failed to update package lists."
  sudo apt-get full-upgrade -y -qq -o Dpkg::Options::="--force-overwrite" || handle_error "System update failed."
  sudo apt-get autoremove -y -qq || handle_error "Autoremove failed."
  sudo apt-get autoclean -y -qq || handle_error "Autoclean failed."
  sudo apt-get install -y -qq aptitude || handle_error "Failed to install aptitude."
}

install_basic_packages() {
  local packages=(
    plocate build-essential llvm pkg-config autoconf automake cmake cmake-data
    autopoint ninja-build gettext libtool libtool-bin g++ make meson clang gcc
    nasm clang-tools clangd clang-format dkms curl wget ca-certificates ranger
    lsb-release gawk git git-lfs zsh tmux ffmpeg gnome-tweaks inxi most tree
    nautilus-admin tar jq pixz net-tools blender lzma unzip fastfetch playerctl
    fonts-font-awesome mypaint timidity gir1.2-gtk-3.0 ttfautohint bear zeal
    v4l2loopback-dkms htop gnupg fzf bc ripgrep gdebi rar imagemagick
    gir1.2-ayatanaappindicator3-0.1 dialog asciidoc uthash-dev hashdeep file
    gnome-shell-extension-manager polkitd pkexec policykit-1-gnome usbview
    hwdata v4l-utils flatpak python-is-python3 ipython3 python3-pip python3-dev
    valac python3-babel python3-dbus python3-pynvim python3-sphinx
    python3-packaging libopencv-dev blueprint-compiler transmission
    python3-venv pipx vlc fakeroot pavucontrol pulseaudio-utils btop
    python3-gi python3-gi-cairo python3-cairo python3-setuptools p7zip-full
    zsh-autosuggestions zsh-syntax-highlighting  lnav multitail gource ccze
    fortune network-manager-openvpn
    wofi wl-clipboard wtype
    qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virtinst
    virt-manager virt-viewer cloud-image-utils libguestfs-tools virtiofsd
  )

  print_info "Installing basic packages ..."
  if ! sudo debconf-apt-progress -- apt-get install -y "${packages[@]}"; then
    handle_error "Failed to install one or more packages."
  fi
}

install_wine() {
  print_info "Installing Wine ..."
  sudo apt install -y --install-recommends \
    wine64 wine32 wine32:i386 libwine libwine:i386 winetricks ||
    handle_error "Failed to install Wine."
}

install_dev_libs() {
  local devlibs=(
    libffi-dev libxml2-dev libegl1-mesa-dev libgles2-mesa-dev libgbm-dev
    libinput-dev libglm-dev libgtkmm-3.0-dev libdrm-dev libseat-dev
    libgirepository1.0-dev libsystemd-dev libdbusmenu-gtk3-dev
    libxkbregistry-dev libdisplay-info-dev libev-dev libgtk-3-dev
    libgtk-4-dev libwebkit2gtk-4.1-dev libsdl1.2-dev libssl-dev
    libayatana-appindicator3-dev librsvg2-dev libnotify-bin libgl-dev
    libfontconfig1-dev libfreetype-dev lxc-dev libpango1.0-dev libyajl-dev
    libjson-c-dev libconfig-dev libdbus-1-dev libegl-dev libpcre2-dev
    libpixman-1-dev libcmark-dev libxkbcommon-dev libnl-genl-3-dev
    libuv1-dev libcairo2-dev libjsoncpp-dev libsecret-1-dev libkrb5-dev
    libconfuse-dev libasound2-dev libiw-dev libpulse-dev libmpdclient-dev
    libcurl4-openssl-dev libgl1-mesa-dev libncurses5-dev libreadline-dev
    libglew-dev libsdl2-dev libz3-dev libjpeg-dev libfluidsynth-dev libgme-dev
    libopenal-dev libopenal-data libmpg123-dev libsndfile1-dev zlib1g-dev
    libglvnd-dev mesa-common-dev libegl1 libgles-dev libgles1 libglvnd-core-dev
    libopengl-dev libgif-dev libwxgtk3.2-dev libwxgtk3.2-1t64 libwxbase3.2-1t64
    libwxsvg-dev libftgl-dev libfreeimage-dev liblua5.4-dev
    libwxgtk-webview3.2-dev libadwaita-1-dev libwireplumber-0.5-dev
    libdmapsharing-4.0-dev libswresample-dev python3-qtpy python3-pyqt5
    pyqt5-dev-tools qttools5-dev-tools python3-pyqt6 pyqt6-dev-tools qtchooser
    pyliblo-utils libepoxy-dev libvpx-dev libbz2-dev
  )

  print_info "Installing dev libs ..."
  if ! sudo debconf-apt-progress -- apt-get install -y "${devlibs[@]}"; then
    handle_error "Failed to install one or more dev libs."
  fi
}

update_plocate_db() {
  print_info "Updating plocate database ..."
  sudo updatedb || handle_error "Failed to update the file database."
}

install_recipes() {
  sudo apt-get autoremove -y -qq || handle_error "Autoremove failed."
  sudo apt-get autoclean -y -qq || handle_error "Autoclean failed."

  local recipe_dir
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  recipe_dir="${SCRIPT_DIR}/z_setup_scripts"

  local recipes=(
    "$recipe_dir/install_flatpak.sh"
    "$recipe_dir/install_neovim.sh"
    "$recipe_dir/install_vscode.sh"
    "$recipe_dir/install_nvm.sh"
    "$recipe_dir/install_node.sh"
    "$recipe_dir/install_brave.sh"
    "$recipe_dir/install_fanatec.sh"
    "$recipe_dir/install_lazygit.sh"
    "$recipe_dir/install_gcloud.sh"
    "$recipe_dir/install_cloudflared.sh"
    "$recipe_dir/install_githubcli.sh"
    "$recipe_dir/install_tmuxpm.sh"
    "$recipe_dir/install_zig.sh"
    "$recipe_dir/install_rust.sh"
    "$recipe_dir/install_golang.sh"
    "$recipe_dir/install_deno.sh"
    "$recipe_dir/install_bun.sh"
    "$recipe_dir/install_pnpm.sh"
    "$recipe_dir/install_emscripten.sh"
    "$recipe_dir/install_eza.sh"
    "$recipe_dir/install_docker.sh"
    "$recipe_dir/install_dockercompose.sh"
    "$recipe_dir/install_nvidiacontainertk.sh"
    "$recipe_dir/install_fd.sh"
    "$recipe_dir/install_alacritty.sh"
    "$recipe_dir/install_ytdlp.sh"
    "$recipe_dir/install_urblind.sh"
    "$recipe_dir/fix_cedilla.sh"
    "$recipe_dir/install_nginx.sh"
    "$recipe_dir/install_oh-my-zsh.sh"
    "$recipe_dir/install_powerlevel10k.sh"
    "$recipe_dir/install_ghostty.sh"
  )

  for recipe in "${recipes[@]}"; do
    if [ -f "$recipe" ]; then
      print_info "Running recipe: $(basename "$recipe")"
      # shellcheck source=/dev/null
      source "$recipe" || handle_error "Failed to execute recipe: $(basename "$recipe")"
    else
      print_warning "Recipe not found: $(basename "$recipe")"
    fi
  done
}

link_dotfiles() {
  local target_home="$HOME"
  local target_config="$HOME/.config"
  local target_local_share="$HOME/.local/share"

  mkdir -p "$target_config/Code/User"
  mkdir -p "$target_config/VSCodium/User"
  mkdir -p "$target_config/systemd/user"
  mkdir -p "$target_config/environment.d"

  declare -A files_to_link=(
    ["${DOTDOT}/profile/profile"]="$target_home/.profile"
    ["${DOTDOT}/bash/bashrc"]="$target_home/.bashrc"
    ["${DOTDOT}/bash/inputrc"]="$target_home/.inputrc"
    ["${DOTDOT}/zsh/zshrc"]="$target_home/.zshrc"
    ["${DOTDOT}/zsh/zshenv"]="$target_home/.zshenv"
    ["${DOTDOT}/p10k/p10k.zsh"]="$target_home/.p10k.zsh"
    ["${DOTDOT}/tmux/tmux.conf"]="$target_home/.tmux.conf"
    ["${DOTDOT}/x/XCompose"]="$target_home/.XCompose"
    ["${DOTDOT}/vst3"]="$target_home/.vst3"
    ["${DOTDOT}/yabridgectl"]="$target_config/yabridgectl"
    ["${DOTDOT}/ghostty"]="$target_config/ghostty"
    ["${DOTDOT}/nvim"]="$target_config/nvim"
    ["${DOTDOT}/wofi"]="$target_config/wofi"
    ["${DOTDOT}/alacritty"]="$target_config/alacritty"
    ["${DOTDOT}/vscode/settings.json"]="$target_config/Code/User/settings.json"
    ["${DOTDOT}/vscodium/settings.json"]="$target_config/VSCodium/User/settings.json"
    ["${DOTDOT}/local/share/yabridge"]="$target_local_share/yabridge"
    ["${DOTDOT}/environment.d"]="$target_config/environment.d"
    ["${DOTDOT}/local/share/ghostty"]="$target_local_share/ghostty"
    ["${DOTDOT}/fonts"]="$target_home/.fonts"
    ["${DOTDOT}/systemd/user/virtual-mic.service"]="$target_config/systemd/user/virtual-mic.service"
  )

  for source_file in "${!files_to_link[@]}"; do
    local target_file="${files_to_link[$source_file]}"
    link_file "$source_file" "$target_file"
  done
  fc-cache -f || handle_error "Failed to update font cache."
}

install_snap_packages() {
  print_info "Snap SUCKS! No packages to install."
  # print_info "Installing snap packages ..."
  # install_with_snap discord
  # install_with_snap kdiskmark
  # install_with_snap spotify
}

install_flatpak_packages() {
  sudo apt-get install -y -qq flatpak || handle_error "Failed to install flatpak."
  sudo apt-get install -y -qq gnome-software-plugin-flatpak || handle_error "Failed to install gnome-software-plugin-flatpak."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  local flatpak_apps_to_install=(
    com.discordapp.Discord
    com.obsproject.Studio
    org.gimp.GIMP
    com.valvesoftware.Steam
    net.davidotek.pupgui2
    com.github.Matoking.protontricks
    org.prismlauncher.PrismLauncher
    org.mozilla.firefox
    net.pcsx2.PCSX2
  )

  print_info "Installing flatpak packages ..."
  for app in "${flatpak_apps_to_install[@]}"; do
    if flatpak list --app | grep -q "$app"; then
      print_info "$app is already installed ..."
    else
      print_info "Installing $app ..."
      flatpak install -y flathub "$app"
      mkdir -p "$HOME/.var/app/$app"
    fi
  done

  print_success "Flatpak packages installed successfully."
}

link_launchers() {
  print_info "Linking launchers ..."
  local launchers_list=(
    "${DOTDOT}/launchers/alacritty.desktop"
    "${DOTDOT}/launchers/chrome-webgl.desktop"
    "${DOTDOT}/launchers/chrome-webgpu.desktop"
  )

  for launcher in "${launchers_list[@]}"; do
    local target="${HOME}/.local/share/applications/$(basename "$launcher")"
    rm -f "$target"
    link_file "$launcher" "$target"
    print_info "Linked $launcher to $target"
  done
  update-desktop-database "$ME"/.local/share/applications
}

update_cache() {
  print_info "Updating fonts cache ..."
  fc-cache -f || handle_error "Failed to update font cache."
  sudo updatedb || handle_error "Failed to update the file database."
}

post_install() {
  sudo usermod -a -G audio $USER
  sudo usermod -a -G kvm $USER
  sudo usermod -a -G libvirt $USER
  systemctl --user daemon-reexec
  systemctl --user daemon-reload
  systemctl --user enable --now virtual-mic.service
  sudo loginctl enable-linger $USER
}

update_system

install_basic_packages
install_dev_libs
install_wine
update_plocate_db

install_recipes
install_snap_packages
install_flatpak_packages

link_dotfiles
link_launchers

update_cache

post_install
update_system
