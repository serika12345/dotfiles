{
  pkgs,
  ...
}:

let
  delaySeconds = 20;
  stateDir = "/run/staged-suspend";
  lockFile = "/run/staged-suspend.lock";
  desktopUser = "masato";
  protonDriveMount = "/home/${desktopUser}/ProtonDrive";
  rcloneUnit = "rclone-protondrive.service";
  userManager = "${desktopUser}@.host";
  displayWakeNotification = "${stateDir}/display-woke";

  stagedSuspendDisplayControl = pkgs.writeShellApplication {
    name = "staged-suspend-display-control";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      display_service=org.gnome.Mutter.DisplayConfig
      display_path=/org/gnome/Mutter/DisplayConfig
      display_interface=org.gnome.Mutter.DisplayConfig
      wake_notification=${displayWakeNotification}

      find_local_graphical_session() {
        local active class name remote seat session type uid

        while read -r session _; do
          if ! active="$(
            loginctl show-session "$session" --property=Active --value 2>/dev/null
          )"; then
            continue
          fi
          [ "$active" = yes ] || continue

          remote="$(
            loginctl show-session "$session" --property=Remote --value
          )"
          [ "$remote" = no ] || continue

          seat="$(
            loginctl show-session "$session" --property=Seat --value
          )"
          [ "$seat" = seat0 ] || continue

          type="$(
            loginctl show-session "$session" --property=Type --value
          )"
          case "$type" in
            wayland | x11) ;;
            *) continue ;;
          esac

          class="$(
            loginctl show-session "$session" --property=Class --value
          )"
          case "$class" in
            user | greeter) ;;
            *) continue ;;
          esac

          name="$(
            loginctl show-session "$session" --property=Name --value
          )"
          uid="$(
            loginctl show-session "$session" --property=User --value
          )"
          if [ -n "$name" ] && [ -n "$uid" ]; then
            printf '%s %s\n' "$name" "$uid"
            return 0
          fi
        done < <(loginctl list-sessions --no-legend)

        echo "No active local graphical session found" >&2
        return 1
      }

      user_busctl() {
        local name target uid

        target="$(find_local_graphical_session)"
        read -r name uid <<<"$target"
        runuser --user "$name" -- \
          env \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            busctl --user "$@"
      }

      get_power_save_mode() {
        local property

        property="$(
          user_busctl get-property \
            "$display_service" \
            "$display_path" \
            "$display_interface" \
            PowerSaveMode
        )"
        printf '%s\n' "''${property##* }"
      }

      set_power_save_mode() {
        user_busctl set-property \
          "$display_service" \
          "$display_path" \
          "$display_interface" \
          PowerSaveMode i "$1"
      }

      watch_display_wake() {
        local mode

        rm -f "$wake_notification"
        while true; do
          if ! mode="$(get_power_save_mode)"; then
            # GDM hands seat0 to the user's GNOME session during login. Retry
            # across that short interval instead of losing wake detection.
            sleep 0.1
            continue
          fi
          if [ "$mode" = 0 ]; then
            touch "$wake_notification"
            exit 0
          fi
          sleep 0.1
        done
      }

      case "''${1:-}" in
        on)
          # MetaPowerSave: ON=0.
          set_power_save_mode 0
          ;;
        off)
          # MetaPowerSave: OFF=3.
          set_power_save_mode 3
          ;;
        watch)
          watch_display_wake
          ;;
        *)
          echo "usage: staged-suspend-display-control {on|off|watch}" >&2
          exit 2
          ;;
      esac
    '';
  };

  stagedSuspendControl = pkgs.writeShellApplication {
    name = "staged-suspend-control";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      state_dir=${stateDir}
      armed_file="$state_dir/armed"
      suspending_file="$state_dir/suspending"
      cooldown_file="$state_dir/resume-cooldown"
      rclone_active_file="$state_dir/rclone-was-active"
      display_wake_notification=${displayWakeNotification}
      lock_file=${lockFile}
      delay_timer=staged-suspend-delay.timer
      cooldown_timer=staged-suspend-cooldown.timer
      rclone_resume_timer=staged-suspend-rclone-resume.timer
      display_wake_service=staged-suspend-display-wake.service
      display_on_service=staged-suspend-display-on.service
      rclone_unit=${rcloneUnit}

      prepare_state_dir() {
        install -d -m 0700 "$state_dir"
      }

      lock_state() {
        exec 9>"$lock_file"
        flock 9
      }

      unlock_state() {
        flock -u 9
      }

      user_systemctl() {
        systemctl --user --machine=${userManager} "$@"
      }

      turn_display_on() {
        systemctl restart "$display_on_service" || true
      }

      cancel_pending_suspend() {
        systemctl stop "$display_wake_service" || true
        systemctl stop "$delay_timer" || true
        rm -f "$armed_file" "$suspending_file"
        turn_display_on
        echo "Cancelled pending staged suspend"
      }

      arm_suspend() {
        # Ensure a watcher left over from a just-cancelled request cannot see
        # the new armed state before the display has been blanked.
        systemctl stop "$display_wake_service" || true
        rm -f "$display_wake_notification"

        # Resynchronize Mutter in case an older implementation changed the
        # physical backlight without updating its logical DPMS state.
        turn_display_on
        touch "$armed_file"

        # Lock first so waking the display after a cancellation never exposes
        # the unlocked session.
        loginctl lock-sessions || true
        sleep 0.2

        if ! systemctl restart "$display_wake_service"; then
          rm -f "$armed_file"
          turn_display_on
          return 1
        fi

        if ! systemctl restart "$delay_timer"; then
          cancel_pending_suspend
          return 1
        fi

        echo "Blanked the display; suspend is armed in ${toString delaySeconds} seconds"
      }

      button_pressed() {
        prepare_state_dir
        lock_state

        if [ -e "$cooldown_file" ]; then
          turn_display_on
          echo "Ignored the wake-up power event during the resume cooldown"
        elif [ -e "$armed_file" ] || [ -e "$suspending_file" ]; then
          cancel_pending_suspend
        else
          arm_suspend
        fi
      }

      display_woke() {
        prepare_state_dir
        lock_state
        rm -f "$display_wake_notification"
        if [ -e "$armed_file" ]; then
          cancel_pending_suspend
          echo "Cancelled pending staged suspend after the display woke"
        fi
        unlock_state
      }

      stop_rclone() {
        local rclone_state

        rclone_state="$(user_systemctl is-active "$rclone_unit" 2>/dev/null || true)"
        case "$rclone_state" in
          active | activating | reloading)
            ;;
          *)
            return
            ;;
        esac

        touch "$rclone_active_file"
        if ! timeout 8s systemctl --user --machine=${userManager} stop "$rclone_unit"; then
          echo "rclone did not stop promptly; lazily unmounting Proton Drive" >&2
          /run/wrappers/bin/fusermount3 -uz ${protonDriveMount} || true
        fi
      }

      finish_suspend() {
        status=$?

        trap - EXIT
        lock_state
        touch "$cooldown_file"
        rm -f "$armed_file" "$suspending_file"
        systemctl stop "$display_wake_service" || true
        turn_display_on

        if [ -e "$rclone_active_file" ]; then
          rm -f "$rclone_active_file"
          systemctl restart "$rclone_resume_timer" || true
        fi

        if ! systemctl restart "$cooldown_timer"; then
          rm -f "$cooldown_file"
        fi

        unlock_state
        exit "$status"
      }

      suspend_still_requested() {
        lock_state
        if [ -e "$suspending_file" ]; then
          unlock_state
          return 0
        fi

        unlock_state
        return 1
      }

      wait_for_suspend_cycle() {
        local active_state
        local attempts=0

        # `systemctl suspend` returns once logind has queued the request, before
        # systemd-suspend.service has entered the kernel. Keep this process
        # alive until that service has actually completed so the EXIT cleanup
        # cannot turn the display back on immediately before suspend.
        while true; do
          active_state="$(
            systemctl show \
              --property=ActiveState \
              --value \
              systemd-suspend.service
          )"
          case "$active_state" in
            activating | active | deactivating)
              break
              ;;
          esac

          attempts=$((attempts + 1))
          if [ "$attempts" -ge 200 ]; then
            echo "Timed out waiting for systemd-suspend.service to start" >&2
            return 1
          fi
          sleep 0.05
        done

        while true; do
          active_state="$(
            systemctl show \
              --property=ActiveState \
              --value \
              systemd-suspend.service
          )"
          case "$active_state" in
            activating | active | deactivating)
              sleep 0.1
              ;;
            *)
              break
              ;;
          esac
        done
      }

      commit_suspend() {
        prepare_state_dir
        lock_state

        if [ ! -e "$armed_file" ]; then
          unlock_state
          exit 0
        fi

        mv "$armed_file" "$suspending_file"
        unlock_state
        systemctl stop "$display_wake_service" || true

        trap finish_suspend EXIT
        stop_rclone

        # The power button can still cancel while rclone is being stopped.
        suspend_still_requested

        # Let logind honor block inhibitors, but avoid systemctl's client-side
        # "other logged-in user" check: this helper runs without a TTY as root,
        # so the active desktop session would otherwise be treated as foreign.
        #
        # Mark the wake event as absorbed before entering the kernel. The power
        # button handler can run a few milliseconds before systemd-sleep
        # returns, so creating this only in finish_suspend would be too late.
        touch "$cooldown_file"
        systemctl --check-inhibitors=auto suspend
        wait_for_suspend_cycle
      }

      restart_rclone() {
        if user_systemctl is-active --quiet "$rclone_unit"; then
          exit 0
        fi

        user_systemctl start "$rclone_unit"
      }

      clear_cooldown() {
        prepare_state_dir
        lock_state
        rm -f "$cooldown_file"
        echo "Resume cooldown finished"
      }

      case "''${1:-}" in
        button)
          button_pressed
          ;;
        commit)
          commit_suspend
          ;;
        restart-rclone)
          restart_rclone
          ;;
        clear-cooldown)
          clear_cooldown
          ;;
        display-woke)
          display_woke
          ;;
        *)
          echo "usage: staged-suspend-control {button|commit|restart-rclone|clear-cooldown|display-woke}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  # keyd delays the standalone power action for chord_timeout, so the existing
  # power+volumeup screenshot chord continues to win when both keys are used.
  # Run the actual handler as a separate unit so keyd never blocks on locking,
  # display control, or timer operations.
  services.keyd.keyboards.surfaceButtons.settings.main.power =
    "command(${pkgs.systemd}/bin/systemctl --no-block restart staged-suspend-button.service)";

  systemd.services.staged-suspend-button = {
    description = "Handle a staged-suspend power-button press";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${stagedSuspendControl}/bin/staged-suspend-control button";
    };
  };

  systemd.services.staged-suspend-commit = {
    description = "Commit a staged suspend after the display-off grace period";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${stagedSuspendControl}/bin/staged-suspend-control commit";
      TimeoutStartSec = "infinity";
    };
  };

  systemd.services.staged-suspend-display-wake = {
    description = "Blank the display and watch for a GNOME wake event";
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${stagedSuspendDisplayControl}/bin/staged-suspend-display-control off";
      ExecStart = "${stagedSuspendDisplayControl}/bin/staged-suspend-display-control watch";
    };
  };

  systemd.services.staged-suspend-display-on = {
    description = "Wake the display without changing its brightness";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${stagedSuspendDisplayControl}/bin/staged-suspend-display-control on";
    };
  };

  systemd.services.staged-suspend-display-woke = {
    description = "Cancel staged suspend after a GNOME display wake event";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${stagedSuspendControl}/bin/staged-suspend-control display-woke";
    };
  };

  systemd.paths.staged-suspend-display-woke = {
    description = "Watch for a GNOME display wake notification";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathExists = displayWakeNotification;
      Unit = "staged-suspend-display-woke.service";
    };
  };

  systemd.timers.staged-suspend-delay = {
    description = "Delay suspend after the power button blanks the display";
    timerConfig = {
      OnActiveSec = "${toString delaySeconds}s";
      AccuracySec = "100ms";
      Unit = "staged-suspend-commit.service";
    };
  };

  systemd.services.staged-suspend-cooldown = {
    description = "Finish the staged-suspend wake-event cooldown";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${stagedSuspendControl}/bin/staged-suspend-control clear-cooldown";
    };
  };

  systemd.timers.staged-suspend-cooldown = {
    description = "Absorb the power event that woke the system";
    timerConfig = {
      OnActiveSec = "3s";
      AccuracySec = "100ms";
      Unit = "staged-suspend-cooldown.service";
    };
  };

  systemd.services.staged-suspend-rclone-resume = {
    description = "Remount Proton Drive after resume";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${stagedSuspendControl}/bin/staged-suspend-control restart-rclone";
      TimeoutStartSec = "90s";
    };
  };

  systemd.timers.staged-suspend-rclone-resume = {
    description = "Give networking time to recover before remounting Proton Drive";
    timerConfig = {
      OnActiveSec = "10s";
      AccuracySec = "1s";
      Unit = "staged-suspend-rclone-resume.service";
    };
  };

  environment.systemPackages = [ stagedSuspendControl ];
}
