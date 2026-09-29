{ pkgs, ... }:

let
  # The 2026-04-28 vendor image contains the gralloc_handler rewrite from
  # 2025-07-16 and crashes while reading metadata from a null layer handle.
  # Keep the last matching LineageOS 20 image pair from before that rewrite
  # until an official image includes upstream fix b5f7e358c3b5d7ea5c1e449966746316f485ca50.
  imageVersion = "2025-07-12";

  mkWaydroidImage =
    {
      imageName,
      variant,
      url,
      hash,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "waydroid-${imageName}-${variant}-image";
      version = imageVersion;

      src = pkgs.fetchurl {
        inherit url hash;
      };

      nativeBuildInputs = [ pkgs.unzip ];
      dontUnpack = true;

      installPhase = ''
        runHook preInstall

        mkdir -p "$out"
        unzip -j "$src" "${imageName}.img" -d "$out"
        test -s "$out/${imageName}.img"

        runHook postInstall
      '';
    };

  systemImage = mkWaydroidImage {
    imageName = "system";
    variant = "vanilla";
    url = "https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20250712-VANILLA-waydroid_x86_64-system.zip/download";
    hash = "sha256-uoLE5XiNTt4GyV6Z3yg1YUcj3a+zC6ZXR1cOxlEGUfw=";
  };

  vendorImage = mkWaydroidImage {
    imageName = "vendor";
    variant = "mainline";
    url = "https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/lineage-20.0-20250712-MAINLINE-waydroid_x86_64-vendor.zip/download";
    hash = "sha256-FIY4GYhBGZI5QKvhoSDvJltN7edwNvVZeHfMY+D9he4=";
  };
in
{
  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };

  # Waydroid treats this path as preinstalled images and refuses in-place OTA
  # updates, so the known-good pair remains pinned by the Nix configuration.
  environment.etc."waydroid-extra/images/system.img".source = "${systemImage}/system.img";
  environment.etc."waydroid-extra/images/vendor.img".source = "${vendorImage}/vendor.img";

  systemd.services.waydroid-container.preStart = ''
    set -eu

    waydroid_config=/var/lib/waydroid/waydroid.cfg
    if [ ! -f "$waydroid_config" ]; then
      echo "Waydroid is not initialized; run 'sudo waydroid init' once." >&2
      exit 1
    fi

    intel_render_node=
    for node_path in /sys/class/drm/renderD*; do
      [ -e "$node_path/device/vendor" ] || continue
      [ "$(< "$node_path/device/vendor")" = 0x8086 ] || continue
      intel_render_node="/dev/dri/''${node_path##*/}"
      break
    done

    if [ -z "$intel_render_node" ]; then
      echo "No Intel DRM render node was found for Waydroid." >&2
      exit 1
    fi

    set_waydroid_option() {
      option_name=$1
      option_value=$2

      if ${pkgs.gnugrep}/bin/grep -q "^$option_name[[:space:]]*=" "$waydroid_config"; then
        ${pkgs.gnused}/bin/sed -i \
          "s|^$option_name[[:space:]]*=.*$|$option_name = $option_value|" \
          "$waydroid_config"
      else
        ${pkgs.gnused}/bin/sed -i \
          "/^\[waydroid\][[:space:]]*$/a $option_name = $option_value" \
          "$waydroid_config"
      fi
    }

    set_waydroid_option images_path /etc/waydroid-extra/images
    set_waydroid_option system_datetime 0
    set_waydroid_option vendor_datetime 0
    set_waydroid_option system_ota None
    set_waydroid_option vendor_ota None

    ${pkgs.gnused}/bin/sed -i \
      '/^gralloc\.gbm\.legacy[[:space:]]*=/d' \
      "$waydroid_config"

    if ${pkgs.gnugrep}/bin/grep -q '^gralloc\.gbm\.device[[:space:]]*=' "$waydroid_config"; then
      ${pkgs.gnused}/bin/sed -i \
        "s|^gralloc\.gbm\.device[[:space:]]*=.*$|gralloc.gbm.device = $intel_render_node|" \
        "$waydroid_config"
    else
      ${pkgs.gnused}/bin/sed -i \
        "/^\[properties\][[:space:]]*$/a gralloc.gbm.device = $intel_render_node" \
        "$waydroid_config"
    fi

    for property_file in \
      /var/lib/waydroid/waydroid_base.prop \
      /var/lib/waydroid/waydroid.prop
    do
      [ -f "$property_file" ] || continue

      ${pkgs.gnused}/bin/sed -i \
        -e '/^gralloc\.gbm\.legacy=/d' \
        -e '/^waydroid\.system_ota=/d' \
        -e '/^waydroid\.vendor_ota=/d' \
        -e '/^waydroid\.updater\.disabled=/d' \
        "$property_file"

      if ${pkgs.gnugrep}/bin/grep -q '^gralloc\.gbm\.device=' "$property_file"; then
        ${pkgs.gnused}/bin/sed -i \
          "s|^gralloc\.gbm\.device=.*$|gralloc.gbm.device=$intel_render_node|" \
          "$property_file"
      else
        ${pkgs.gnused}/bin/sed -i \
          "$ a gralloc.gbm.device=$intel_render_node" \
          "$property_file"
      fi

      ${pkgs.gnused}/bin/sed -i \
        '$ a waydroid.updater.disabled=true' \
        "$property_file"
    done
  '';
}
