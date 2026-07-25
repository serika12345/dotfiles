# Replace this file with /etc/nixos/hardware-configuration.nix generated on the
# installed Surface before the first `nixos-rebuild switch --flake`.
#
# This checked-in version intentionally contains only hardware-independent
# defaults. In particular, guessing the root and EFI partition identifiers here
# would make the resulting system unbootable.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
