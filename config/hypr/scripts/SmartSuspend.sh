#!/bin/bash
# Decide suspend method based on power source:
# - On battery: prefer suspend-then-hibernate (respects HibernateDelaySec)
# - On AC: plain suspend

set -euo pipefail

is_on_ac() {
    for ps in /sys/class/power_supply/*; do
        [ -d "$ps" ] || continue
        if [ -f "$ps/type" ] && grep -qiE 'mains|ac|usb' "$ps/type"; then
            if [ -f "$ps/online" ] && [ "$(cat "$ps/online")" = "1" ]; then
                return 0
            fi
        fi
    done
    return 1
}

if is_on_ac; then
    exec systemctl suspend || exec loginctl suspend
else
    # Try suspend-then-hibernate so the kernel/logind handles the delay
    systemctl suspend-then-hibernate || systemctl suspend || loginctl suspend
fi
