# After a reboot, getty@tty1 auto-logs in with HYPR_AUTOLOGIN=1 set
# (/etc/systemd/system/getty@tty1.service.d/autologin.conf). Start Hyprland,
# which locks itself right away (see hypr/custom/execs.conf).
# Manual logins don't have the marker and behave as before.
# Escape hatch: touch ~/.no-hypr-autostart (log in on tty2 with Ctrl+Alt+F2).
if status is-login; and test "$HYPR_AUTOLOGIN" = 1; and test (tty) = /dev/tty1
    and not set -q WAYLAND_DISPLAY; and not test -e ~/.no-hypr-autostart
    exec ~/.local/bin/start-hyprland
end
