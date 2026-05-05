{ pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      # fcitx5-mozc
      fcitx5-mozc-ut
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.xrdp = {
    enable = true;
    # XRDP では Plasma の X11 セッションを使う
    defaultWindowManager = "startplasma-x11";
    # Open the default RDP port (3389)
    openFirewall = true;
  };

  # KDE/Qt integration
  programs.kdeconnect.enable = true;
}
