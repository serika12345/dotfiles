{ pkgs, ... }:

let
  kritaWayland = pkgs.symlinkJoin {
    name = "krita-wayland";
    paths = [ pkgs.krita ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/krita" --set QT_QPA_PLATFORM wayland
    '';
  };
in
{
  environment.systemPackages = [ kritaWayland ];

  # The Surface Pen's tail button sends Meta+F20 for a single click. Rewrite
  # F20 as F12 at device creation time so that even the first event after the
  # Bluetooth device wakes cannot trigger GNOME's Meta+F20 action.
  services.udev.extraHwdb = ''
    evdev:input:b0005v045Ep0921*
     KEYBOARD_KEY_7006f=f12
  '';

  # Keep Krita's brush smoothing defaults reproducible without managing the
  # entire mutable kritarc file. In Krita's config, DistanceMin is the sample
  # count at maximum speed and DistanceMax is the count at minimum speed.
  home-manager.users.masato.home.activation.kritaBrushSmoothing = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      kritarc="$config_dir/kritarc"
      kwriteconfig=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6

      run ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingType 3
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingDistanceKeepAspectRatio --type bool false
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingDistanceMin 3
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingDistanceMax 50
    '';
  };

  # Keep the main UI out of the way while drawing. The standard popup palette
  # and Docker Box provide touch-friendly access to frequently used controls.
  home-manager.users.masato.home.activation.kritaPopupPalette = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      kritarc="$config_dir/kritarc"
      kritashortcutsrc="$config_dir/kritashortcutsrc"
      input_dir="$HOME/.local/share/krita/input"
      input_profile="$input_dir/kritadefault.profile"
      kwriteconfig=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6

      run ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
      run ${pkgs.coreutils}/bin/mkdir -p "$input_dir"
      run ${pkgs.coreutils}/bin/cp --no-clobber \
        ${pkgs.krita}/share/krita/input/kritadefault.profile \
        "$input_profile"
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key hideDockersFullScreen --type bool true
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key showBrushHud --type bool true
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key "popuppalette/dockerList" KisLayerBox
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key "popuppalette/currentDocker" KisLayerBox
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key "toolbar/dockerList" \
        "BrushHudDocker,PresetDocker,ColorSelectorNg,KisLayerBox"
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key "toolbar/currentDocker" BrushHudDocker
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key "dockerBox/dockerList" --delete ""
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key "dockerBox/currentDocker" --delete ""
      run "$kwriteconfig" --file "$kritashortcutsrc" \
        --group Shortcuts --key docker_box "Meta+F12"
      run "$kwriteconfig" --file "$input_profile" \
        --group "Show Popup Widget" --key 1 --delete ""
      run "$kwriteconfig" --file "$input_profile" \
        --group "Show Popup Widget" --key 2 --delete ""
    '';
  };
}
