{
  # Keep enough headroom for systemd-oomd to react before the kernel OOM
  # killer has to select an arbitrary process.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  # zram is backed by RAM, so use a lower-priority disk swap as the final
  # reserve for incompressible or sustained memory pressure.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8 * 1024;
      priority = 10;
    }
  ];

  # Terminate the control group responsible for sustained pressure before
  # the whole machine becomes unresponsive.
  systemd.oomd = {
    enable = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  # Use all eight logical CPUs for a large derivation and allow two
  # independent derivations to overlap while the memory limits below contain
  # unusually memory-intensive builds.
  nix.settings = {
    max-jobs = 2;
    cores = 8;
  };

  # Slow builds down under pressure, then contain an OOM within Nix while
  # retaining memory and swap for the desktop and remote administration.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "10G";
    MemoryMax = "12G";
    MemorySwapMax = "2G";
    OOMPolicy = "kill";
    OOMScoreAdjust = 500;
  };

  # Preserve enough memory for interactive sessions when system services,
  # containers, or Nix builds are responsible for the pressure.
  systemd.slices.user.sliceConfig.MemoryLow = "1G";

  # Keep the SSH listener and networking available so the machine remains
  # recoverable even if an existing login session is terminated.
  systemd.services.sshd.serviceConfig = {
    OOMScoreAdjust = -900;
    ManagedOOMPreference = "avoid";
    MemoryLow = "64M";
  };

  systemd.services.NetworkManager.serviceConfig = {
    OOMScoreAdjust = -800;
    ManagedOOMPreference = "avoid";
    MemoryLow = "64M";
  };

  # GDM is small enough to protect and provides a way to start a fresh GNOME
  # session after systemd-oomd terminates a memory-intensive application.
  systemd.services.display-manager.serviceConfig = {
    OOMScoreAdjust = -500;
    ManagedOOMPreference = "avoid";
    MemoryLow = "256M";
  };
}
