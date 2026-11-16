#!/bin/bash
# Removes everything install.sh put in place. The fault log /var/log/touchpad-i2c.log is kept.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

systemctl disable --now touchpad-rebind.service touchpad-i2c-log.service 2>/dev/null || true
rm -f /usr/local/bin/touchpad-fix \
      /usr/local/sbin/touchpad-rebind.sh \
      /usr/local/sbin/touchpad-i2c-log.sh \
      /etc/systemd/system/touchpad-rebind.service \
      /etc/systemd/system/touchpad-i2c-log.service
systemctl daemon-reload

if [ -e /etc/dracut.conf.d/90-loq-touchpad-acpi.conf ] || [ -e /etc/acpi-override/ssdt-loq-touchpad.aml ]; then
  rm -f /etc/dracut.conf.d/90-loq-touchpad-acpi.conf \
        /etc/acpi-override/ssdt-loq-touchpad.dsl \
        /etc/acpi-override/ssdt-loq-touchpad.aml
  rmdir /etc/acpi-override 2>/dev/null || true
  echo "Rebuilding the initramfs for kernel $(uname -r) without the ACPI table..."
  dracut -f
  echo "The ACPI table is gone from the next boot on."
fi

echo "Removed. The fault log /var/log/touchpad-i2c.log was left in place."
echo "If you added the keyboard shortcut, remove it as your normal user:  ./install-shortcut.sh --remove"
