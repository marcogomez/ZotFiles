#!/usr/bin/env bash
#
# lock-apt-packages.sh — deterministically snapshot the apt packages that were
# explicitly installed on this machine, categorize them, and generate
# ready-to-paste setup.sh install functions into:
#
#     packages/apt-install-functions.sh
#
# Ground truth (no human memory involved):
#   - apt-mark showmanual          -> the set of packages apt records as
#                                     explicitly requested (not dependencies).
#   - dpkg metadata                -> Section / Priority / Essential fields
#                                     drive classification and categorization.
#   - apt-cache policy             -> repository origin of the installed
#                                     version (Release "o=Ubuntu" field, so it
#                                     is mirror-hostname agnostic).
#
# Classification pipeline (first match wins):
#   1. Essential:yes or Priority required/important  -> skipped (present on
#      any Ubuntu install; listed in a comment block for audit).
#   2. Matches EXCLUDE_PATTERNS                      -> skipped (wanted on
#      this machine but deliberately kept out of setup.sh; listed in a
#      comment block for audit).
#   3. Installed version not available from an Ubuntu-origin repo
#      -> skipped (installed by z_setup_scripts recipes or local .debs;
#      listed in a comment block with origins for audit).
#   4. Explicit per-package override table           -> that category.
#   5. dpkg Section (component prefix stripped)      -> category via table.
#   6. Anything left -> "uncategorized" comment block + warning. Nothing is
#      ever silently dropped.
#
# Re-running on the same system state reproduces the output byte-for-byte.
#
# Usage: ./lock-apt-packages.sh [--manifest]
#   --manifest  also write apt-manifest-versions.tsv (every installed package
#               with version/arch/section/manual-flag; noisy across upgrades,
#               useful as a point-in-time record).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="${SCRIPT_DIR}/apt-install-functions.sh"
NATIVE_ARCH="$(dpkg --print-architecture)"
WRITE_MANIFEST="no"
[ "${1:-}" = "--manifest" ] && WRITE_MANIFEST="yes"

# dpkg Section -> category. Sections not listed here fall through to
# "uncategorized" so new sections are surfaced instead of guessed at.
declare -A SECTION_MAP=(
  [libdevel]=dev-libs
  [introspection]=dev-libs
  [devel]=dev-tools
  [vcs]=dev-tools
  [interpreters]=dev-tools
  [javascript]=dev-tools
  [perl]=dev-tools
  [ruby]=dev-tools
  [java]=dev-tools
  [golang]=dev-tools
  [rust]=dev-tools
  [python]=python
  [utils]=cli-tools
  [text]=cli-tools
  [shells]=cli-tools
  [math]=cli-tools
  [misc]=cli-tools
  [web]=cli-tools
  [admin]=system
  [kernel]=system
  [net]=system
  [httpd]=system
  [mail]=system
  [comm]=system
  [database]=system
  [metapackages]=system
  [otherosfs]=virtualization
  [libs]=runtime-libs
  [oldlibs]=runtime-libs
  [sound]=multimedia
  [video]=multimedia
  [graphics]=multimedia
  [gnome]=desktop
  [x11]=desktop
  [xfce]=desktop
  [editors]=desktop
  [games]=desktop
  [doc]=desktop
  [fonts]=fonts
  [localization]=locale-docs
  [translations]=locale-docs
)

# Per-package overrides, applied before the section map. Keep this table
# small: it exists for packages whose dpkg Section is technically true but
# operationally wrong for setup.sh (e.g. wine has its own install function
# because of the i386 dance).
declare -A PACKAGE_OVERRIDES=(
  [wine64]=wine
  [wine32:i386]=wine
  [libwine]=wine
  [libwine:i386]=wine
  [winetricks]=wine
  # Transitional packages whose dpkg Section is "oldlibs" but that are
  # really dev tooling / virtualization tools.
  [pkg-config]=dev-tools
  [libgl1-mesa-dev]=dev-libs
  [libgles2-mesa-dev]=dev-libs
  [libgirepository1.0-dev]=dev-libs
  [libfontconfig1-dev]=dev-libs
  [virtinst]=virtualization
  # dpkg files these under "admin"/"net", but they belong with the qemu
  # stack from a user's point of view.
  [libvirt-clients]=virtualization
  [libvirt-daemon-system]=virtualization
  [virt-manager]=virtualization
  [virt-viewer]=virtualization
  [cloud-image-utils]=virtualization
  [libguestfs-tools]=virtualization
  # Section says "admin"/"net"/"oldlibs"; perception says otherwise.
  [tmux]=cli-tools
  [lnav]=cli-tools
  [transmission]=desktop
  [imagemagick]=multimedia
  # GL/audio/wx runtime libs that pair with their -dev packages.
  [libegl1]=dev-libs
  [libegl1:i386]=dev-libs
  [libgles1]=dev-libs
  [libopenal-data]=dev-libs
  [libwxbase3.2-1t64]=dev-libs
  [libwxgtk3.2-1t64]=dev-libs
  # Compilers/tools misfiled under "gnome"/"devel"/"libdevel".
  [blueprint-compiler]=dev-tools
  [uthash-dev]=dev-libs
  [qtchooser]=dev-tools
  # Secure Boot / boot stack: dpkg files these under "utils", but they
  # belong next to grub-efi-amd64/efibootmgr, not between ripgrep and tmux.
  [shim-signed]=system
  [grub-efi-amd64-signed]=system
)

# Glob patterns for packages that stay on this machine but must not be baked
# into setup.sh. They end up in an audit comment block, never in a function.
EXCLUDE_PATTERNS=(
  # Kernel stack: every Ubuntu install already ships and upgrades its own
  # kernel; the manual marks came from the installer, and the names are
  # pinned to a kernel version / driver series that goes stale.
  'linux-headers-*'
  'linux-image-*'
  'linux-generic-*'
  'linux-modules-*'
  # NVIDIA driver: version-pinned by the installer's third-party-drivers
  # step; belongs in a dedicated recipe (ubuntu-drivers / pinned install),
  # not in a generic package list.
  'nvidia-driver-*'
  # Locale support: the installer seeds language packs for whatever locale
  # is picked at install time; listing them here is redundant.
  'language-pack-*'
)

# Order in which the generated install functions appear (and should run).
CATEGORY_ORDER=(
  system cli-tools dev-tools dev-libs python runtime-libs
  desktop multimedia virtualization fonts locale-docs
)

# Build the set of repo URLs whose Release file declares Origin "Ubuntu".
# Matching on o= instead of hostnames keeps this correct across mirrors
# (gb.archive.ubuntu.com, security.ubuntu.com, country mirrors, ...).
declare -A UBUNTU_REPO_URLS=()
build_ubuntu_repo_set() {
  local url="" line
  while IFS= read -r line; do
    case "$line" in
      *" Packages") url="$(awk '{print $2}' <<<"$line")" ;;
      *"release "*)
        if [[ "$line" == *"o=Ubuntu,"* ]] && [ -n "$url" ]; then
          UBUNTU_REPO_URLS["$url"]=1
        fi
        url=""
        ;;
    esac
  done < <(apt-cache policy)
}

is_excluded() {
  local pkg="$1" pattern
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    # shellcheck disable=SC2254
    case "$pkg" in $pattern) return 0 ;; esac
  done
  return 1
}

# Print the repo URLs providing the *installed* version of a package
# (the lines under the "***" entry in apt-cache policy's version table).
installed_version_sources() {
  apt-cache policy "$1" 2>/dev/null | awk '
    /^ \*\*\* / { inblock = 1; next }
    inblock && /^ +[0-9]+ / { print $2; next }
    inblock { inblock = 0 }
  '
}

# Emit "$@" as array-literal lines: 4-space indent, wrapped at 78 columns.
emit_wrapped() {
  local line="" pkg
  for pkg in "$@"; do
    if [ -z "$line" ]; then
      line="    $pkg"
    elif [ $((${#line} + 1 + ${#pkg})) -le 78 ]; then
      line="$line $pkg"
    else
      printf '%s\n' "$line"
      line="    $pkg"
    fi
  done
  [ -n "$line" ] && printf '%s\n' "$line"
}

echo "Building Ubuntu-origin repo set ..."
build_ubuntu_repo_set
if [ "${#UBUNTU_REPO_URLS[@]}" -eq 0 ]; then
  echo "ERROR: no repos with Origin 'Ubuntu' found via apt-cache policy." >&2
  exit 1
fi

echo "Classifying $(apt-mark showmanual | wc -l) manually-installed packages ..."

declare -A BUCKET=() # category -> newline-joined package lines

add_to() { BUCKET["$1"]+="$2"$'\n'; }

while IFS=$'\t' read -r pkg section priority essential; do
  # Strip native arch qualifier (libfoo:amd64 -> libfoo); keep foreign arch.
  pkg="${pkg%:"$NATIVE_ARCH"}"
  # Strip archive component prefix (non-free/libs -> libs).
  section="${section##*/}"

  # 1. Guaranteed-present base system: audit only.
  if [ "$essential" = "yes" ] || [ "$priority" = "required" ] || [ "$priority" = "important" ]; then
    add_to "base-system" "$pkg"
    continue
  fi

  # 2. Deliberately kept out of setup.sh: audit only.
  if is_excluded "$pkg"; then
    add_to "excluded" "$pkg"
    continue
  fi

  # 3. Installed version not served by an Ubuntu-origin repo: recipe-managed.
  ubuntu_origin="no"
  first_source=""
  while IFS= read -r src; do
    [ -n "$first_source" ] || first_source="$src"
    [ -n "${UBUNTU_REPO_URLS[$src]:-}" ] && ubuntu_origin="yes"
  done < <(installed_version_sources "$pkg")
  if [ "$ubuntu_origin" = "no" ]; then
    add_to "third-party" "$pkg ($first_source)"
    continue
  fi

  # 4. Explicit override.
  if [ -n "${PACKAGE_OVERRIDES[$pkg]:-}" ]; then
    add_to "${PACKAGE_OVERRIDES[$pkg]}" "$pkg"
    continue
  fi

  # 5. Section map, 6. fallback.
  category="${SECTION_MAP[$section]:-}"
  if [ -n "$category" ]; then
    add_to "$category" "$pkg"
  else
    add_to "uncategorized" "$pkg (section=${section:-none})"
  fi
done < <(apt-mark showmanual | xargs dpkg-query -W \
  -f='${binary:Package}\t${Section}\t${Priority}\t${Essential}\n')

sorted_bucket() { printf '%s' "${BUCKET[$1]:-}" | LC_ALL=C sort; }

{
  echo "# apt install functions — generated by packages/lock-apt-packages.sh"
  echo "# Copy the functions below into setup.sh (or source this file)."
  echo "# Do not edit by hand: re-run the generator and it will be overwritten."
  echo

  echo "# --- not included: base system (present on any Ubuntu install) -------------"
  sorted_bucket base-system | sed 's/^/#   /'
  echo
  echo "# --- not included: third-party origins (installed by recipes/local debs) ---"
  sorted_bucket third-party | sed 's/^/#   /'
  echo

  if [ -n "${BUCKET[excluded]:-}" ]; then
    echo "# --- not included: excluded by policy (EXCLUDE_PATTERNS in the generator) ---"
    sorted_bucket excluded | sed 's/^/#   /'
    echo
  fi

  if [ -n "${BUCKET[uncategorized]:-}" ]; then
    echo "# --- WARNING: uncategorized (extend SECTION_MAP in the generator) -----------"
    sorted_bucket uncategorized | sed 's/^/#   /'
    echo
  fi

  for category in "${CATEGORY_ORDER[@]}"; do
    [ -n "${BUCKET[$category]:-}" ] || continue
    mapfile -t pkgs < <(sorted_bucket "$category")
    label="${category//-/ }"
    echo "install_${category//-/_}() {"
    echo "  local packages=("
    emit_wrapped "${pkgs[@]}"
    echo "  )"
    echo
    echo "  print_info \"Installing ${label} packages ...\""
    echo "  if ! sudo debconf-apt-progress -- apt-get install -y \"\${packages[@]}\"; then"
    echo "    handle_error \"Failed to install one or more ${label} packages.\""
    echo "  fi"
    echo "}"
    echo
  done

  # Wine keeps its own function: it needs i386 packages and recommends.
  if [ -n "${BUCKET[wine]:-}" ]; then
    mapfile -t pkgs < <(sorted_bucket wine)
    echo "install_wine() {"
    echo "  print_info \"Installing Wine ...\""
    echo "  sudo apt install -y --install-recommends \\"
    echo "    ${pkgs[*]} ||"
    echo "    handle_error \"Failed to install Wine.\""
    echo "}"
    echo
  fi
} >"$OUT_FILE"

for category in base-system excluded third-party uncategorized "${CATEGORY_ORDER[@]}" wine; do
  [ -n "${BUCKET[$category]:-}" ] || continue
  count="$(sorted_bucket "$category" | wc -l)"
  printf '  %-16s %3d packages\n' "$category" "$count"
done

if [ -n "${BUCKET[uncategorized]:-}" ]; then
  echo "WARNING: uncategorized packages present — see $OUT_FILE" >&2
fi

if [ "$WRITE_MANIFEST" = "yes" ]; then
  {
    echo -e "# package\tversion\tarch\tsection\tmark"
    join -t $'\t' -a1 -o '1.1,1.2,1.3,1.4,2.2' -e manual \
      <(dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\t${Section}\n' | LC_ALL=C sort) \
      <(apt-mark showauto | sed 's/$/\tauto/' | LC_ALL=C sort)
  } >"${SCRIPT_DIR}/apt-manifest-versions.tsv"
  echo "Wrote full version manifest: ${SCRIPT_DIR}/apt-manifest-versions.tsv"
fi

echo "Done: generated $OUT_FILE"
