```bash
#!/usr/bin/env bash
set -euo pipefail

# Install fcitx5-mozc and related packages for X11 desktop environments,
# then configure input-method environment variables.

PACKAGES=(
  fcitx5
  fcitx5-mozc
  fcitx5-configtool
  fcitx5-gtk
  fcitx5-qt
  fcitx5-im
)

err() { printf 'Error: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }

add_line_if_missing() {
  # Usage: add_line_if_missing "LINE" "FILE"
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

install_packages() {
  need_cmd pacman

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    info "Installing packages with pacman..."
    pacman -Syu --needed --noconfirm "${PACKAGES[@]}"
  else
    need_cmd sudo
    info "Installing packages with sudo pacman..."
    sudo pacman -Syu --needed --noconfirm "${PACKAGES[@]}"
  fi
}

configure_env_user() {
  local profile="$HOME/.profile"
  local xprofile="$HOME/.xprofile"

  info "Configuring environment variables for this user..."

  # .profile (login shells)
  add_line_if_missing 'export GTK_IM_MODULE=fcitx' "$profile"
  add_line_if_missing 'export QT_IM_MODULE=fcitx' "$profile"
  add_line_if_missing 'export XMODIFIERS=@im=fcitx' "$profile"
  add_line_if_missing 'export SDL_IM_MODULE=fcitx' "$profile"
  add_line_if_missing 'export GLFW_IM_MODULE=fcitx' "$profile"

  # .xprofile (some display managers / X11 sessions source this)
  add_line_if_missing 'export GTK_IM_MODULE=fcitx' "$xprofile"
  add_line_if_missing 'export QT_IM_MODULE=fcitx' "$xprofile"
  add_line_if_missing 'export XMODIFIERS=@im=fcitx' "$xprofile"
  add_line_if_missing 'export SDL_IM_MODULE=fcitx' "$xprofile"
  add_line_if_missing 'export GLFW_IM_MODULE=fcitx' "$xprofile"
}

configure_env_systemwide() {
  # Writes /etc/profile.d/fcitx5.sh (preferred) and appends to /etc/environment (optional).
  # Requires root.
  local profiled="/etc/profile.d/fcitx5.sh"
  local envfile="/etc/environment"

  info "Configuring environment variables system-wide..."

  cat >"$profiled" <<'EOF'
# Fcitx5 input method environment variables
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=fcitx
EOF
  chmod 0644 "$profiled"

  # /etc/environment uses KEY=VALUE (no "export"). Keep it minimal and idempotent.
  grep -q '^GTK_IM_MODULE=fcitx$' "$envfile" 2>/dev/null || echo 'GTK_IM_MODULE=fcitx' >>"$envfile"
  grep -q '^QT_IM_MODULE=fcitx$'  "$envfile" 2>/dev/null || echo 'QT_IM_MODULE=fcitx'  >>"$envfile"
  grep -q '^XMODIFIERS=@im=fcitx$' "$envfile" 2>/dev/null || echo 'XMODIFIERS=@im=fcitx' >>"$envfile"
  grep -q '^SDL_IM_MODULE=fcitx$' "$envfile" 2>/dev/null || echo 'SDL_IM_MODULE=fcitx' >>"$envfile"
  grep -q '^GLFW_IM_MODULE=fcitx$' "$envfile" 2>/dev/null || echo 'GLFW_IM_MODULE=fcitx' >>"$envfile"
}

configure_autostart_x11() {
  # Ensure fcitx5 starts automatically in X11 sessions.
  local autostart_dir="$HOME/.config/autostart"
  local desktop_file="$autostart_dir/fcitx5.desktop"

  mkdir -p "$autostart_dir"

  info "Creating XDG autostart entry for fcitx5 (user)..."
  cat >"$desktop_file" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx5
Comment=Start Fcitx5 Input Method
Exec=fcitx5 -d
OnlyShowIn=GNOME;KDE;XFCE;LXDE;LXQt;MATE;Cinnamon;i3;awesome;dwm;Openbox;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  chmod 0644 "$desktop_file"
}

main() {
  install_packages

  # Environment variables:
  # - Always configure per-user (works without root).
  configure_env_user

  # If running as root, also configure system-wide.
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    configure_env_systemwide
  else
    info "Not running as root: skipping system-wide env configuration."
    info "If you want system-wide settings, re-run with sudo: sudo $0"
  fi

  configure_autostart_x11

  info ""
  info "Done."
  info "Log out and log back in (or reboot) to apply environment variables."
  info "Then open 'Fcitx 5 Configuration' and add 'Mozc' as an input method."
}

main "$@"
```
