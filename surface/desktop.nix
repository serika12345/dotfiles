{
  lib,
  pkgs,
  ...
}:

let
  inherit (lib.gvariant) mkInt32 mkTuple mkUint32;
in
{
  # GNOME's on-screen keyboard follows IBus input sources, so use Mozc through
  # IBus instead of the Fcitx5 setup used by the desktop machine.
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ mozc-ut ];
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
  home-manager.users.masato.xdg.dataFile."gnome-shell/extensions/keyboard-toggle@SAH046.github.io".source =
    "${pkgs.gnomeExtensions.keyboard-toggle}/share/gnome-shell/extensions/keyboard-toggle@SAH046.github.io";
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
      current = mkUint32 1;
      sources = [
        (mkTuple [
          "xkb"
          "jp"
        ])
        (mkTuple [
          "ibus"
          "mozc-jp"
        ])
      ];
      mru-sources = [
        (mkTuple [
          "ibus"
          "mozc-jp"
        ])
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
      # Settings > Power > Automatic Suspend > When Plugged In
      sleep-inactive-ac-type = "nothing";
    };

    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
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
