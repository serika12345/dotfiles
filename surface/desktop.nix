{
  lib,
  pkgs,
  ...
}:

let
  inherit (lib.gvariant) mkInt32 mkTuple mkUint32;
in
{
  # TODO: Remove this overlay and surface/patches/mutter-text-input-v1-osk.patch
  # once nixpkgs ships Mutter 50.3 or later, which contains upstream MR !5117.
  # Mutter 50.2 removed the implicit input-panel request used by version 1
  # text-input clients when it added version 2 of the protocol. GTK 4.22 still
  # binds version 1, so retain the old fallback until the upstream fix is used.
  nixpkgs.overlays = [
    (final: prev: {
      mutter = prev.mutter.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ./patches/mutter-text-input-v1-osk.patch
        ];
      });
    })
  ];

  # GNOME's on-screen keyboard follows IBus input sources, so use Mozc through
  # IBus instead of the Fcitx5 setup used by the desktop machine.
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ mozc-ut ];
    # TODO: Re-evaluate this explicit setting when the NixOS IBus Wayland
    # frontend becomes the default; keep using the compositor's text-input
    # protocol rather than forcing the legacy IBus toolkit modules.
    ibus.waylandFrontend = true;
  };

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.gnome.gcr-ssh-agent.enable = false;

  services.gnome.core-apps.enable = false;
  services.gnome.core-developer-tools.enable = true;
  services.gnome.games.enable = false;

  environment.gnome.excludePackages = with pkgs; [
    cheese
    epiphany
    geary
    gnome-calendar
    gnome-clocks
    gnome-connections
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-tour
    gnome-user-docs
    gnome-weather
    simple-scan
    totem
    yelp
  ];

  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];
  documentation.nixos.enable = false;

  programs.dconf.enable = true;
  # Write these values to the user's dconf database. System profile values are
  # only defaults and lose to values already stored by a previous GNOME login.
  home-manager.users.masato.xdg.configFile."mozc/ibus_config.textproto" = {
    # Replace the configuration file initially created by Mozc.
    force = true;
    text = ''
      engines {
        name : "mozc-jp"
        longname : "Mozc"
        layout : "default"
        layout_variant : ""
        layout_option : ""
        rank : 80
        symbol : "あ"
      }
      engines {
        name : "mozc-on"
        longname : "Mozc:あ"
        layout : "default"
        layout_variant : ""
        layout_option : ""
        rank : 99
        symbol : "あ"
        composition_mode : HIRAGANA
      }
      engines {
        name : "mozc-off"
        longname : "Mozc:A_"
        layout : "default"
        layout_variant : ""
        layout_option : ""
        rank : 99
        symbol : "A"
        composition_mode : DIRECT
      }
      active_on_launch: False
      mozc_renderer {
        # Use GNOME's IBus candidate UI so candidates appear on the OSK.
        enabled : False
      }
    '';
  };
  home-manager.users.masato.xdg.dataFile."gnome-shell/extensions/keyboard-toggle@SAH046.github.io".source =
    "${pkgs.gnomeExtensions.keyboard-toggle}/share/gnome-shell/extensions/keyboard-toggle@SAH046.github.io";
  # GNOME gives an empty suggestions row less height than a row containing
  # candidate buttons. Keep the row at a constant height so Mozc updates do not
  # make the whole on-screen keyboard jump.
  home-manager.users.masato.xdg.dataFile."gnome-shell/extensions/fixed-osk-suggestions-height@local".source =
    ./gnome-shell-extensions/fixed-osk-suggestions-height;
  home-manager.users.masato.dconf.settings = {
    "org/gnome/desktop/a11y/applications" = {
      screen-keyboard-enabled = true;
    };

    "org/gnome/desktop/interface" = {
      accent-color = "blue";
      clock-format = "24h";
      clock-show-date = true;
      color-scheme = "prefer-dark";
      scaling-factor = mkUint32 2;
      show-battery-percentage = true;
      toolkit-accessibility = true;
    };

    "org/gnome/desktop/input-sources" = {
      current = mkUint32 0;
      sources = [
        (mkTuple [
          "ibus"
          "mozc-on"
        ])
        (mkTuple [
          "ibus"
          "mozc-off"
        ])
      ];
      mru-sources = [
        (mkTuple [
          "ibus"
          "mozc-on"
        ])
        (mkTuple [
          "ibus"
          "mozc-off"
        ])
      ];
      per-window = false;
      show-all-sources = false;
      xkb-model = "pc105+inet";
      xkb-options = [ "ctrl:nocaps" ];
    };

    "org/gnome/settings-daemon/peripherals/touchscreen" = {
      orientation-lock = false;
    };

    "org/gnome/settings-daemon/plugins/power" = {
      # Settings > Power > Dim Screen
      idle-dim = false;
      # Settings > Power > Automatic Screen Brightness
      ambient-enabled = false;
      # Settings > Power > Automatic Power Saver
      power-saver-profile-on-low-battery = false;
      # Suspend when the physical power button is pressed.
      power-button-action = "suspend";
      # Settings > Power > Automatic Suspend > When Plugged In
      sleep-inactive-ac-type = "nothing";
    };

    "org/gnome/shell" = {
      # GNOME hides Log Out for a single local user with one session unless
      # this is enabled. Keep it available from the power menu.
      always-show-log-out = true;
      disable-user-extensions = false;
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "fixed-osk-suggestions-height@local"
        "keyboard-toggle@SAH046.github.io"
        "no-overview@fthx"
      ];
      favorite-apps = [
        "firefox.desktop"
        "org.kde.krita.desktop"
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "org.gnome.Settings.desktop"
      ];
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      autohide = false;
      background-opacity = 0.8;
      dash-max-icon-size = mkInt32 48;
      dock-fixed = true;
      dock-position = "LEFT";
      extend-height = true;
      intellihide = false;
      show-apps-at-top = false;
    };
  };

  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    gnome-console
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    gnomeExtensions.no-overview
    nautilus
  ];
}
