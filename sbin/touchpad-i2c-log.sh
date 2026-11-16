#!/bin/bash
# Logs touchpad I2C fault bursts (Lenovo LOQ 15IAX9, FocalTech FTCS0038 on i2c_designware.0)
# to /var/log/touchpad-i2c.log with wall-clock time and seconds since the last resume.
LOG=/var/log/touchpad-i2c.log
last_resume=$(date +%s)
echo "$(date "+%F %T") logger started (boot $(cat /proc/sys/kernel/random/boot_id))" >> "$LOG"
journalctl -f -k -n 0 -o cat | while IFS= read -r line; do
  case "$line" in
    *"PM: suspend exit"*) last_resume=$(date +%s); echo "$(date "+%F %T") resume" >> "$LOG" ;;
    *i2c_designware.0*"lost arbitration"*|*i2c_designware.0*"timed out"*|*i2c_designware.0*"spurious STOP"*|*FTCS0038*"incomplete report"*|*FTCS0038*"-121"*|*FTCS0038*"failed to"*)
      now=$(date +%s); echo "$(date "+%F %T") +$((now-last_resume))s since resume: ${line#*kernel: }" >> "$LOG" ;;
  esac
done
