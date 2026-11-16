#!/bin/bash
# Installs the touchpad workaround for the Lenovo LOQ 15IAX9 (83GS) with the
# FocalTech FTCS0038 touchpad. See README.md.
#
#   ./install.sh             install everything (asks for sudo)
#   ./install.sh --no-acpi   skip the ACPI table and leave the initramfs alone
#   ./install.sh --force     install the scripts on a different model (never the ACPI table)
set -euo pipefail

MODEL=83GS
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
acpi=1
force=0

die() { echo "install.sh: $*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --no-acpi) acpi=0 ;;
    --force)   force=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument '$arg' (try --help)" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
if [ "$product" != "$MODEL" ]; then
  [ "$force" = 1 ] || die "this machine is '$product', not a Lenovo LOQ 15IAX9 ($MODEL). Use --force to install the scripts anyway."
  echo "Not a $MODEL: installing the scripts only, without the ACPI table."
  acpi=0
fi

# --- packages -----------------------------------------------------------------
pkgs=()
command -v i2ctransfer >/dev/null 2>&1 || pkgs+=(i2c-tools)
if [ "$acpi" = 1 ]; then
  command -v iasl   >/dev/null 2>&1 || pkgs+=(acpica-tools)
  command -v dracut >/dev/null 2>&1 || die "dracut not found; rerun with --no-acpi or load the ACPI table your distribution's way."
fi
if [ "${#pkgs[@]}" -gt 0 ]; then
  command -v dnf >/dev/null 2>&1 || die "please install these packages first: ${pkgs[*]}"
  echo "Installing packages: ${pkgs[*]}"
  dnf install -y "${pkgs[@]}"
fi

# --- command, watchdog, fault logger ---------------------------------------------
echo "Installing touchpad-fix, the auto-rebind watchdog and the fault logger..."
install -m 755 "$here/bin/touchpad-fix"                 /usr/local/bin/touchpad-fix
install -m 755 "$here/sbin/touchpad-rebind.sh"          /usr/local/sbin/touchpad-rebind.sh
install -m 755 "$here/sbin/touchpad-i2c-log.sh"         /usr/local/sbin/touchpad-i2c-log.sh
install -m 644 "$here/systemd/touchpad-rebind.service"  /etc/systemd/system/touchpad-rebind.service
install -m 644 "$here/systemd/touchpad-i2c-log.service" /etc/systemd/system/touchpad-i2c-log.service
systemctl daemon-reload
systemctl enable touchpad-rebind.service touchpad-i2c-log.service
systemctl restart touchpad-rebind.service touchpad-i2c-log.service

# --- ACPI table (makes the touchpad exist on boots where the BIOS fails to detect it) ---
if [ "$acpi" = 1 ]; then
  echo "Compiling and installing the ACPI table..."
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  iasl -p "$tmp/ssdt-loq-touchpad" "$here/acpi/ssdt-loq-touchpad.dsl" > "$tmp/iasl.log" 2>&1 \
    || { cat "$tmp/iasl.log" >&2; die "iasl could not compile the ACPI table"; }

  changed=0
  cmp -s "$tmp/ssdt-loq-touchpad.aml" /etc/acpi-override/ssdt-loq-touchpad.aml || changed=1
  cmp -s "$here/acpi/90-loq-touchpad-acpi.conf" /etc/dracut.conf.d/90-loq-touchpad-acpi.conf || changed=1

  install -d /etc/acpi-override
  install -m 644 "$here/acpi/ssdt-loq-touchpad.dsl"       /etc/acpi-override/ssdt-loq-touchpad.dsl
  install -m 644 "$tmp/ssdt-loq-touchpad.aml"             /etc/acpi-override/ssdt-loq-touchpad.aml
  install -m 644 "$here/acpi/90-loq-touchpad-acpi.conf"   /etc/dracut.conf.d/90-loq-touchpad-acpi.conf

  if [ "$changed" = 1 ]; then
    echo "Rebuilding the initramfs for kernel $(uname -r) (this takes a minute)..."
    dracut -f
    echo "The ACPI table is loaded from the next boot on. Kernels installed later pick it up automatically."
  else
    echo "ACPI table already installed and unchanged; initramfs left as it is."
  fi
fi

echo
echo "Done. Try:  touchpad-fix status"
