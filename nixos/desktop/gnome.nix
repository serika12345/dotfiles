{ pkgs, lib, ... }:
let
  inherit (lib.gvariant) mkTuple;
  remoteLoginUser = "masato";
  desktopSharingUser = "masato";
  grdStateDir = "/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop";
  grdCertPath = "${grdStateDir}/tls.crt";
  grdKeyPath = "${grdStateDir}/tls.key";
in
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc-ut
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };

  # GNOMEの自動サスペンドを無効化(上記とは別系統なのでこれもやらないとダメっぽい)
  services.displayManager.gdm.autoSuspend = false;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # GNOMEの同梱アプリ群を大きく削る
  services.gnome.core-apps.enable = false;
  services.gnome.core-developer-tools.enable = true;
  services.gnome.games.enable = false;

  # 残るものを個別除外
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    gnome-user-docs
    epiphany
    geary
    yelp
    gnome-maps
    gnome-music
    totem
    cheese
    simple-scan
    seahorse
    gnome-weather
    gnome-calendar
    gnome-clocks
    gnome-contacts
    gnome-connections
  ];

  # GNOME外の同梱物
  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];
  documentation.nixos.enable = false;

  # Enable the GNOME RDP components
  services.gnome.gnome-remote-desktop.enable = true;

  # Ensure the service starts automatically at boot so the settings panel appears
  systemd.services.gnome-remote-desktop = {
    wantedBy = [ "graphical.target" ];
  };

  systemd.services.gnome-remote-desktop-prepare = {
    description = "Prepare GNOME Remote Desktop Remote Login assets";
    before = [ "gnome-remote-desktop.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "gnome-remote-desktop";
      Group = "gnome-remote-desktop";
      StateDirectory = "gnome-remote-desktop";
    };
    script = ''
      mkdir -p "${grdStateDir}"

      if [ ! -s "${grdKeyPath}" ] || [ ! -s "${grdCertPath}" ]; then
        ${pkgs.openssl}/bin/openssl req \
          -x509 \
          -newkey rsa:4096 \
          -nodes \
          -sha256 \
          -days 3650 \
          -subj "/CN=${remoteLoginUser}" \
          -keyout "${grdKeyPath}" \
          -out "${grdCertPath}"
      fi
    '';
  };

  # Open the default RDP port (3389)
  networking.firewall.allowedTCPPorts = [ 3389 ];

  # Disable autologin to avoid session conflicts
  services.displayManager.autoLogin.enable = false;
  services.getty.autologinUser = null;

  home-manager.users.masato = {
    gtk.enable = true;

    home.pointerCursor = {
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    xdg.desktopEntries.fcitx5-config = {
      name = "Fcitx 5 Settings";
      genericName = "Input Method Settings";
      exec = "${pkgs.qt6Packages.fcitx5-configtool}/bin/fcitx5-configtool";
      icon = "tool";
      categories = [
        "Settings"
        "Utility"
      ];
      terminal = false;
    };

    dconf.settings = {
      "org/gnome/desktop/input-sources" = {
        current = 0;
        sources = [
          (mkTuple [
            "xkb"
            "jp"
          ])
        ];

        mru-sources = [
          (mkTuple [
            "xkb"
            "jp"
          ])
        ];

        per-window = false;
        show-all-sources = false;
        xkb-model = "pc105+inet";
        xkb-options = [ "ctrl:nocaps" ];
      };

      "org/gnome/desktop/interface" = {
        accent-color = "blue";
        clock-format = "24h";
        clock-show-date = true;
        clock-show-seconds = false;
        clock-show-weekday = false;
        cursor-theme = "Adwaita";
        cursor-size = 24;
        color-scheme = "prefer-dark";
      };

      # ショートカットが競合するのを防ぐため、入力ソースの切り替えショートカットを無効化。
      "org/gnome/desktop/wm/keybindings" = {
        switch-input-source = [ ];
        switch-input-source-backward = [ ];
      };

      # GNOME Settings の "Desktop Sharing" / "Remote Login" に対応する dconf。
      # 実用には別途 `grd-remote-login-setup` / `grd-desktop-sharing-setup` が必要。
      "org/gnome/desktop/remote-desktop/rdp" = {
        enable = true;
        view-only = false;
        screen-share-mode = "extend";
      };

      "org/gnome/desktop/remote-desktop/rdp/headless" = {
        enable = true;
        port = 3389;
        negotiate-port = false;
      };
    };
  };

  home-manager.users.masato.xdg.configFile = {
    "fcitx5/config".source = ./fcitx5/config;
    "fcitx5/profile".source = ./fcitx5/profile;
  };

  environment.systemPackages = with pkgs; [
    # 残したいGNOMEアプリは明示的に追加
    gnome-console
    nautilus
    # 他のデスクトップ系システムパッケージ
    adwaita-icon-theme
    qt6Packages.fcitx5-configtool
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock # ドックを常に表示するために必要
    gnomeExtensions.kimpanel # GNOME Shell に Input Method Panel を表示
    gnomeExtensions.no-overview # 起動時にオーバービューを表示しない
    (writeShellApplication {
      name = "gnome-reset-to-nixos";
      runtimeInputs = [
        coreutils
        dconf
        findutils
        glib
        gnome-remote-desktop
        systemd
      ];
      text = ''
        set -euo pipefail

        sudo_cmd='/run/wrappers/bin/sudo'
        reset_remote_desktop=1
        assume_yes=0

        usage() {
          cat <<'EOF'
        Usage: gnome-reset-to-nixos [--yes] [--keep-remote-desktop]

          --yes                  Skip the confirmation prompt
          --keep-remote-desktop  Keep GNOME Remote Desktop certificates and credentials
        EOF
        }

        for arg in "$@"; do
          case "$arg" in
            --yes)
              assume_yes=1
              ;;
            --keep-remote-desktop)
              reset_remote_desktop=0
              ;;
            -h|--help)
              usage
              exit 0
              ;;
            *)
              echo "Unknown option: $arg" >&2
              usage >&2
              exit 1
              ;;
          esac
        done

        if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
          echo "Run this command from a GNOME Terminal inside your graphical session." >&2
          exit 1
        fi

        echo "This will reset GNOME state managed outside NixOS/Home Manager:"
        echo "  - dconf keys under /org/gnome, /org/gtk, /org/freedesktop"
        echo "  - user-installed GNOME Shell extensions and caches"
        echo "  - user-level portal / remote desktop service state"
        if [[ "$reset_remote_desktop" -eq 1 ]]; then
          echo "  - system and user GNOME Remote Desktop certificates / credentials"
        fi

        if [[ "$assume_yes" -ne 1 ]]; then
          read -r -p "Continue? [y/N] " reply
          if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
          fi
        fi

        for unit in \
          dconf.service \
          gnome-remote-desktop.service \
          xdg-desktop-portal.service \
          xdg-desktop-portal-gnome.service
        do
          systemctl --user stop "$unit" 2>/dev/null || true
        done

        systemctl --user reset-failed || true

        dconf reset -f /org/gnome/ || true
        dconf reset -f /org/gtk/ || true
        dconf reset -f /org/freedesktop/ || true

        rm -rf \
          "$HOME/.cache/dconf" \
          "$HOME/.cache/gnome-shell" \
          "$HOME/.config/dconf" \
          "$HOME/.local/share/gnome-shell/extensions" \
          "$HOME/.local/share/gnome-shell/extension-updates"

        if [[ "$reset_remote_desktop" -eq 1 ]]; then
          systemctl --user stop gnome-remote-desktop.service 2>/dev/null || true
          rm -rf "$HOME/.local/share/gnome-remote-desktop"

          "$sudo_cmd" systemctl stop gnome-remote-desktop.service 2>/dev/null || true
          "$sudo_cmd" rm -rf "${grdStateDir}"
          "$sudo_cmd" systemctl start gnome-remote-desktop-prepare.service
          "$sudo_cmd" systemctl reset-failed gnome-remote-desktop.service || true
        fi

        for unit in \
          dconf.service \
          xdg-desktop-portal.service \
          xdg-desktop-portal-gnome.service
        do
          systemctl --user start "$unit" 2>/dev/null || true
        done

        if [[ "$reset_remote_desktop" -eq 1 ]]; then
          "$sudo_cmd" systemctl restart gnome-remote-desktop.service
        fi

        echo
        echo "GNOME state was reset."
        echo "Next: run your usual nixos-rebuild/home-manager switch, then log out once."
        if [[ "$reset_remote_desktop" -eq 1 ]]; then
          echo "Remote Desktop credentials were cleared, so rerun grd-remote-login-setup / grd-desktop-sharing-setup if needed."
        fi
      '';
    })
    (writeShellApplication {
      name = "grd-remote-login-setup";
      runtimeInputs = [
        gnome-remote-desktop
        systemd
      ];
      text = ''
        set -euo pipefail

        user_name='${remoteLoginUser}'
        tls_cert='${grdCertPath}'
        tls_key='${grdKeyPath}'
        sudo_cmd='/run/wrappers/bin/sudo'

        if [[ ! -s "$tls_cert" || ! -s "$tls_key" ]]; then
          echo "TLS files are missing. Run 'sudo systemctl start gnome-remote-desktop-prepare.service' first." >&2
          exit 1
        fi

        read -r -p "Remote Login username [$user_name]: " input_user
        if [[ -n "$input_user" ]]; then
          user_name="$input_user"
        fi

        read -r -s -p "Remote Login password: " password
        echo
        read -r -s -p "Confirm password: " password_confirm
        echo

        if [[ -z "$password" ]]; then
          echo "Password must not be empty." >&2
          exit 1
        fi

        if [[ "$password" != "$password_confirm" ]]; then
          echo "Passwords do not match." >&2
          exit 1
        fi

        "$sudo_cmd" grdctl --system rdp set-tls-key "$tls_key"
        "$sudo_cmd" grdctl --system rdp set-tls-cert "$tls_cert"
        "$sudo_cmd" grdctl --system rdp set-credentials "$user_name" "$password"
        "$sudo_cmd" grdctl --system rdp disable-port-negotiation
        "$sudo_cmd" grdctl --system rdp set-port 3389
        "$sudo_cmd" grdctl --system rdp enable
        "$sudo_cmd" systemctl restart gnome-remote-desktop.service

        echo
        echo "Remote Login is configured."
        echo "Username: $user_name"
        echo "Port: 3389"
      '';
    })
    (writeShellApplication {
      name = "grd-desktop-sharing-setup";
      runtimeInputs = [
        gnome-remote-desktop
        openssl
      ];
      text = ''
        set -euo pipefail

        user_name='${desktopSharingUser}'
        state_dir="$HOME/.local/share/gnome-remote-desktop/certificates"
        tls_cert="$state_dir/rdp-tls.crt"
        tls_key="$state_dir/rdp-tls.key"

        mkdir -p "$state_dir"

        if [[ ! -s "$tls_cert" || ! -s "$tls_key" ]]; then
          openssl req \
            -x509 \
            -newkey rsa:4096 \
            -nodes \
            -sha256 \
            -days 3650 \
            -subj "/CN=$user_name" \
            -keyout "$tls_key" \
            -out "$tls_cert"
        fi

        read -r -s -p "Desktop Sharing password for $user_name: " password
        echo
        read -r -s -p "Confirm password: " password_confirm
        echo

        if [[ -z "$password" ]]; then
          echo "Password must not be empty." >&2
          exit 1
        fi

        if [[ "$password" != "$password_confirm" ]]; then
          echo "Passwords do not match." >&2
          exit 1
        fi

        if [[ -z "''${DISPLAY:-}" && -z "''${WAYLAND_DISPLAY:-}" ]]; then
          echo "Run this command from a GNOME Terminal inside an active graphical session." >&2
          exit 1
        fi

        echo "If the Login keyring is locked, a GUI unlock prompt may appear."

        grdctl rdp set-tls-key "$tls_key"
        grdctl rdp set-tls-cert "$tls_cert"
        grdctl rdp set-credentials "$user_name" "$password"
        grdctl rdp disable-view-only
        grdctl rdp enable

        echo
        echo "Desktop Sharing is configured."
        echo "Username: $user_name"
        echo "Port: 3389"
      '';
    })
  ];

  programs.dconf.enable = true;

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = [
            "appindicatorsupport@rgcjonas.gmail.com"
            "dash-to-dock@micxgx.gmail.com"
            "kimpanel@kde.org"
            "no-overview@fthx"
          ];
          favorite-apps = [
            "firefox.desktop"
            "bitwarden.desktop"
            "code.desktop"
            "org.gnome.Nautilus.desktop"
            "org.gnome.Console.desktop"
            "org.gnome.Settings.desktop"
          ];
        };

        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-fixed = true;
          autohide = false;
          intellihide = false;
        };
      };
    }
  ];
}
