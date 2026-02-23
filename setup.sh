#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run as root."
  fi
}

pkg_exists_pacman() {
  local p="$1"
  pacman -Si "$p" >/dev/null 2>&1
}

pkg_exists_yay() {
  local p="$1"
  command -v yay >/dev/null 2>&1 || return 1
  yay -Si "$p" >/dev/null 2>&1
}

detect_target_user() {
  local u=""
  u="${SUDO_USER:-}"
  if [[ -n "$u" && "$u" != "root" ]]; then
    printf '%s' "$u"
    return 0
  fi

  # pick first human user (uid >= 1000), if any
  u="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
  if [[ -n "$u" ]]; then
    printf '%s' "$u"
    return 0
  fi

  return 1
}

ensure_base_tools() {
  log "Installing base tools..."
  pacman -Syu --noconfirm
  pacman -S --noconfirm --needed \
    base-devel git curl wget ca-certificates \
    vim nano \
    sudo \
    networkmanager \
    xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xprop xorg-xdpyinfo \
    mesa \
    dbus
  systemctl enable --now NetworkManager >/dev/null 2>&1 || true
}

install_yay_as_user() {
  local user="$1"
  if command -v yay >/dev/null 2>&1; then
    log "yay is already installed."
    return 0
  fi

  log "Installing yay (AUR helper) as user: $user"
  local tmpdir
  tmpdir="$(mktemp -d)"
  chown "$user:$user" "$tmpdir"
  sudo -u "$user" bash -lc "cd '$tmpdir' && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"
  rm -rf "$tmpdir"
}

install_packages() {
  log "Installing packages..."
  pacman -S --noconfirm --needed \
    greetd greetd-tuigreet \
    i3-wm i3status i3lock dmenu \
    awesome \
    dwm \
    thunar thunar-archive-plugin thunar-media-tags-plugin tumbler gvfs \
    rofi \
    alacritty \
    tmux \
    neovim \
    fastfetch \
    htop btop \
    autotiling \
    firefox \
    fcitx5 fcitx5-im fcitx5-mozc \
    noto-fonts noto-fonts-extra noto-fonts-emoji \
    terminus-font \
    adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts \
    ttf-jetbrains-mono-nerd
}


write_system_files() {
  log "Writing system configuration files..."

  # Console keymap (JP 106)
  cat > /etc/vconsole.conf <<'EOF'
KEYMAP=jp106
FONT=ter-132n
EOF
  # Xorg keyboard layout
  install -d /etc/X11/xorg.conf.d
  cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "jp"
EndSection
EOF

  # dwm Xsession entry (some setups do not ship one)
  install -d /usr/share/xsessions
  cat > /usr/share/xsessions/dwm.desktop <<'EOF'
[Desktop Entry]
Name=dwm
Comment=Dynamic window manager
Exec=dwm
Type=Application
DesktopNames=dwm
EOF

  # greetd wrapper: run Xorg session via startx (user .xinitrc chooses WM)
  install -d /usr/local/bin
  cat > /usr/local/bin/xsession-wrapper <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Ensure a dbus session for X clients
exec dbus-run-session startx
EOF
  chmod 0755 /usr/local/bin/xsession-wrapper

  # greetd config
  install -d /etc/greetd
  cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-user-session --remember-session --asterisks --xsessions /usr/share/xsessions --cmd i3 --xsession-wrapper /usr/local/bin/xsession-wrapper"
user = "greeter"
EOF

  systemctl enable greetd
}

write_user_files() {
  local user="$1"
  local home
  home="$(getent passwd "$user" | awk -F: '{print $6}')"
  [[ -n "$home" && -d "$home" ]] || die "Home directory not found for user: $user"

  log "Writing user configuration files for: $user ($home)"

  # Directories
  install -d -o "$user" -g "$user" "$home/.config/i3"
  install -d -o "$user" -g "$user" "$home/.config/awesome"
  install -d -o "$user" -g "$user" "$home/.config/rofi"
  install -d -o "$user" -g "$user" "$home/.config/alacritty"
  install -d -o "$user" -g "$user" "$home/.config/nvim"
  install -d -o "$user" -g "$user" "$home/.config/autostart"

  # .xinitrc: choose WM by env var WM (i3/awesome/dwm). Default i3.
  cat > "$home/.xinitrc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Input method
if command -v fcitx5 >/dev/null 2>&1; then
  fcitx5 -d >/dev/null 2>&1 || true
fi

# Default WM
WM="${WM:-i3}"

case "$WM" in
  i3) exec i3 ;;
  awesome) exec awesome ;;
  dwm) exec dwm ;;
  *)
    echo "Unknown WM: $WM (use i3/awesome/dwm)" >&2
    exec i3
    ;;
esac
EOF
  chown "$user:$user" "$home/.xinitrc"
  chmod 0755 "$home/.xinitrc"

  # i3 config (minimal)
  cat > "$home/.config/i3/config" <<'EOF'
set $mod Mod4
font pango:JetBrainsMono Nerd Font 10

exec --no-startup-id autotiling

bindsym $mod+Return exec alacritty
bindsym $mod+d exec rofi -show drun
bindsym $mod+Shift+e exec "i3-msg exit"

bindsym $mod+Shift+r restart
bindsym $mod+Shift+c reload

# basic movement
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
EOF
  chown "$user:$user" "$home/.config/i3/config"

  # awesome: copy default rc.lua if not present
  if [[ ! -f "$home/.config/awesome/rc.lua" ]]; then
    if [[ -f /etc/xdg/awesome/rc.lua ]]; then
      install -o "$user" -g "$user" -m 0644 /etc/xdg/awesome/rc.lua "$home/.config/awesome/rc.lua"
    fi
  fi

  # alacritty (toml)
  cat > "$home/.config/alacritty/alacritty.toml" <<'EOF'
[window]
dynamic_title = true

[font]
size = 11.0

[font.normal]
family = "JetBrainsMono Nerd Font"
EOF
  chown "$user:$user" "$home/.config/alacritty/alacritty.toml"

  # rofi
  cat > "$home/.config/rofi/config.rasi" <<'EOF'
configuration {
  modi: "drun,run,window";
  show-icons: true;
}
EOF
  chown "$user:$user" "$home/.config/rofi/config.rasi"

  # tmux
  cat > "$home/.tmux.conf" <<'EOF'
set -g mouse on
set -g history-limit 20000
setw -g mode-keys vi
EOF
  chown "$user:$user" "$home/.tmux.conf"

  # neovim (minimal)
  cat > "$home/.config/nvim/init.lua" <<'EOF'
vim.o.number = true
vim.o.relativenumber = true
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
EOF
  chown "$user:$user" "$home/.config/nvim/init.lua"

  # IME env vars
  cat > "$home/.profile" <<'EOF'
# fcitx5
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
  chown "$user:$user" "$home/.profile"

  # fastfetch on login (optional, only for bash interactive)
  cat > "$home/.bashrc.d_fastfetch" <<'EOF'
if [[ $- == *i* ]]; then
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
  fi
fi
EOF
  chown "$user:$user" "$home/.bashrc.d_fastfetch"
  if ! grep -q 'bashrc.d_fastfetch' "$home/.bashrc" 2>/dev/null; then
    {
      echo ''
      echo '# local additions'
      echo '[[ -f ~/.bashrc.d_fastfetch ]] && source ~/.bashrc.d_fastfetch'
    } >> "$home/.bashrc"
    chown "$user:$user" "$home/.bashrc"
  fi
}

validate_and_install_extra_packages() {
  local user="$1"

  while true; do
    printf '%s' "Extra packages (space-separated, empty to skip): "
    local raw
    IFS= read -r raw || true
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"

    if [[ -z "$raw" ]]; then
      log "No extra packages requested."
      return 0
    fi

    local -a pkgs=()
    read -r -a pkgs <<<"$raw"

    local -a missing=()
    local p
    for p in "${pkgs[@]}"; do
      if pkg_exists_pacman "$p"; then
        continue
      fi
      if pkg_exists_yay "$p"; then
        continue
      fi
      missing+=("$p")
    done

    if (( ${#missing[@]} > 0 )); then
      log "Some packages were not found:"
      printf '  %s\n' "${missing[@]}"
      log "Re-enter the full string (original): $raw"
      continue
    fi

    log "Installing extra packages..."
    # Prefer pacman first; if pacman fails, try yay for all
    if ! pacman -S --noconfirm --needed "${pkgs[@]}"; then
      log "pacman could not install all. Trying yay..."
      sudo -u "$user" yay -S --noconfirm --needed "${pkgs[@]}"
    fi
    return 0
  done
}

main() {
  require_root

  local user=""
  if ! user="$(detect_target_user)"; then
    die "No non-root user detected. Create a user first, then rerun."
  fi
  log "Target user: $user"

  ensure_base_tools
  install_packages
  write_system_files
  write_user_files "$user"
  install_yay_as_user "$user"
  validate_and_install_extra_packages "$user"

  log "Done."
  log "Notes:"
  log "  - greetd enabled. Reboot to use it."
  log "  - Choose WM by setting env var WM before startx (i3/awesome/dwm). Default: i3"
  log "    Example (from tty): WM=awesome startx"
}

main "$@"