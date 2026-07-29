{ pkgs, ... }:

let
  applyKritaConfig = pkgs.writeShellScript "apply-krita-config" ''
    set -eu

    config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
    kritarc="$config_dir/kritarc"
    kritashortcutsrc="$config_dir/kritashortcutsrc"
    input_dir="$HOME/.local/share/krita/input"
    input_profile="$input_dir/kritadefault.profile"
    kwriteconfig=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6

    ${pkgs.coreutils}/bin/mkdir -p "$config_dir" "$input_dir"
    ${pkgs.coreutils}/bin/cp --no-clobber \
      ${pkgs.krita}/share/krita/input/kritadefault.profile \
      "$input_profile"

    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key LineSmoothingType 3
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key LineSmoothingDistanceKeepAspectRatio --type bool false
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key LineSmoothingDistanceMin 3
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key LineSmoothingDistanceMax 50
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key hideDockersFullScreen --type bool true
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key showBrushHud --type bool true
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key KineticScrollingEnabled --type bool true
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key KineticScrollingGesture --type int 1
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key KineticScrollingSensitivity --type int 75
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key KineticScrollingHideScrollbar --type bool false
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key "popuppalette/dockerList" KisLayerBox
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key "popuppalette/currentDocker" KisLayerBox
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key "toolbar/dockerList" \
      "BrushHudDocker,PresetDocker,ColorSelectorNg,KisLayerBox"
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key "toolbar/currentDocker" BrushHudDocker
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key "dockerBox/dockerList" --delete ""
    "$kwriteconfig" --file "$kritarc" --group "<default>" \
      --key "dockerBox/currentDocker" --delete ""
    "$kwriteconfig" --file "$kritashortcutsrc" \
      --group Shortcuts --key docker_box "Meta+F12"
    "$kwriteconfig" --file "$input_profile" \
      --group "Show Popup Widget" --key 1 --delete ""
    "$kwriteconfig" --file "$input_profile" \
      --group "Show Popup Widget" --key 2 --delete ""
  '';

  kritaWayland = pkgs.symlinkJoin {
    name = "krita-wayland";
    paths = [ pkgs.krita ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/krita" \
        --set QT_QPA_PLATFORM wayland \
        --run ${applyKritaConfig}
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

  # Krita keeps its configuration in memory and writes it back when it exits.
  # Apply the managed keys both during a switch and immediately before launch,
  # so a Krita instance that was open during the switch cannot permanently
  # overwrite them with its previously loaded values.
  home-manager.users.masato.home.activation.kritaConfig = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      run ${applyKritaConfig}
    '';
  };
}
