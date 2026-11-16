#!/bin/bash
# Auto-rebind watchdog for the FocalTech FTCS0038 touchpad (Lenovo LOQ 15IAX9).
#
# Two cases are handled, checked every 5 s:
#  1. The I2C client has no driver (i2c_hid_acpi probes once and gives up silently if the
#     pad does not answer): retry the bind, so the pad comes back by itself when it answers.
#  2. The driver is attached but the pad has stopped answering on the bus (typical after a
#     failed resume): after 3 silent checks in a row the driver is detached, so that case 1
#     re-attaches and re-initialises the pad as soon as it answers again.
#  3. The driver is attached but there is no touchpad input device (the pad's descriptor
#     was read garbled during a bad moment): detach after 2 checks and let case 1 retry.
# A check is one read of the HID descriptor; a silent pad NACKs it and logs nothing in the kernel.
LOG=/var/log/touchpad-i2c.log
DRV=/sys/bus/i2c/drivers/i2c_hid_acpi
ADDR=0x38
INTERVAL=5
SILENT_LIMIT=3
state=unknown
silent=0
noinput=0

note() { echo "$(date "+%F %T") rebind: $*" >> "$LOG"; logger -t touchpad-rebind "$*"; }

# 0 = pad answers, 1 = pad is silent (address NACK), 2 = cannot tell (bus jammed, tool missing)
probe() {
  local bus out
  command -v i2ctransfer >/dev/null 2>&1 || return 2
  bus=$(basename "$(dirname "$(realpath "$1")")"); bus=${bus#i2c-}
  out=$(i2ctransfer -f -y "$bus" "w2@$ADDR" 0x01 0x00 r30 2>&1) && return 0
  case "$out" in *"Remote I/O error"*) return 1 ;; *) return 2 ;; esac
}

modprobe -q i2c-dev 2>/dev/null

while :; do
  found=0
  for c in /sys/bus/i2c/devices/i2c-FTCS0038:*; do
    [ -e "$c" ] || continue
    found=1
    name=$(basename "$c")
    if [ -e "$c/driver" ]; then
      [ "$state" != bound ] && note "$name is bound to $(basename "$(readlink "$c/driver")")"
      state=bound
      probe "$c"
      case $? in
        0) silent=0 ;;
        1) silent=$((silent + 1)) ;;
      esac
      if grep -q 'FTCS0038.*Touchpad' /proc/bus/input/devices; then noinput=0; else noinput=$((noinput + 1)); fi
      if [ "$noinput" -ge 2 ] && [ "$silent" -lt "$SILENT_LIMIT" ]; then
        note "$name: driver attached but no touchpad input device (descriptor read failed); detaching the driver to retry"
        echo -n "$name" > "$DRV/unbind" 2>/dev/null
        state=retry
        silent=0
        noinput=0
      elif [ "$silent" -ge "$SILENT_LIMIT" ]; then
        note "$name: driver attached but the pad stopped answering at $ADDR; detaching the driver, retrying every ${INTERVAL}s"
        echo -n "$name" > "$DRV/unbind" 2>/dev/null
        state=dead
        silent=0
        noinput=0
      fi
    elif [ -d "$DRV" ] && echo -n "$name" > "$DRV/bind" 2>/dev/null; then
      note "touchpad answered again; bound i2c_hid_acpi to $name"
      state=bound
      silent=0
      noinput=0
    else
      [ "$state" != dead ] && note "$name has no driver and the pad does not answer at $ADDR; retrying every ${INTERVAL}s"
      state=dead
    fi
  done
  if [ "$found" = 0 ] && [ "$state" != absent ]; then
    note "no FTCS0038 I2C client present"
    state=absent
  fi
  sleep "$INTERVAL"
done
