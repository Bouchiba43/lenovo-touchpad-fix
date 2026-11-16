# lenovo-touchpad-fix

A workaround for a touchpad that keeps freezing or disappearing on the **Lenovo LOQ 15IAX9 (83GS)**
under Linux. The touchpad is a FocalTech `FTCS0038` (`2808:0106`), an I2C-HID device on the first
Intel LPSS I2C controller (PCI `00:15.0`).

> **This does not repair anything.** On the machine it was written for, the cause is hardware: an
> intermittent connection to the touchpad (cable, connector or the pad itself). These scripts only
> bring the touchpad back as soon as it answers again, and tell you truthfully when it does not.
> The permanent fix is reseating or replacing the touchpad cable or module.

## Is this your problem?

Check `sudo dmesg` or `journalctl -k` for messages like these:

```
i2c_designware i2c_designware.0: i2c_dw_handle_tx_abort: lost arbitration
i2c_designware i2c_designware.0: controller timed out
i2c_hid_acpi i2c-FTCS0038:00: failed to set a report to device: -121
i2c_hid_acpi i2c-FTCS0038:00: PM: failed to resume async: error -121
ACPI BIOS Error (bug): AE_AML_PACKAGE_LIMIT, Index (0x5) is beyond end of object
```

Typical symptoms: the pointer freezes for a few seconds, the touchpad is dead after waking from
sleep, or it is missing for a whole boot.

## Install

Tested on Fedora 44 (needs `dnf`, `systemd` and `dracut`).

```sh
git clone https://github.com/Bouchiba43/lenovo-touchpad-fix.git
cd lenovo-touchpad-fix
./install.sh
```

The installer asks for sudo, refuses to run on any other laptop model, and installs the packages
`i2c-tools` and `acpica-tools` if they are missing.

| Option | Effect |
|---|---|
| `./install.sh --no-acpi` | Skip the ACPI table; the initramfs is not touched. |
| `./install.sh --force` | Install the scripts on a different model. The ACPI table is never installed there. |
| `./uninstall.sh` | Remove everything except the fault log. |

## What gets installed

| Piece | Location | What it does |
|---|---|---|
| `touchpad-fix` | `/usr/local/bin` | Command to recover the touchpad by hand and to show its state. |
| Auto-rebind watchdog | `touchpad-rebind.service` | Checks the touchpad every 5 seconds and re-attaches the driver when the pad answers again. |
| Fault logger | `touchpad-i2c-log.service` | Writes every bus fault, with a timestamp, to `/var/log/touchpad-i2c.log`. Useful as evidence for a warranty claim. |
| ACPI table | `/etc/acpi-override`, loaded from the initramfs | Describes the touchpad to Linux on boots where the BIOS fails to detect it. |

## Usage

```sh
touchpad-fix status   # is the pad really working? changes nothing
touchpad-fix          # restart the driver; reset the I2C controller if the pad stays silent
touchpad-fix --hard   # always reset the I2C controller as well
```

When the pad is silent, `touchpad-fix` keeps retrying for two minutes. Pressing firmly on the
touchpad and the palm rest around it has brought it back before. If the pad does not answer on
the bus at all, no software reset can reach it; the watchdog keeps retrying in the background
and re-attaches it by itself once it answers.

## How it works

**The watchdog** handles three stuck states that the kernel does not recover from on its own:

1. The touchpad has no driver. `i2c_hid_acpi` probes once and gives up silently if the pad does
   not answer at that moment. The watchdog retries the bind every 5 seconds.
2. The driver is attached but the pad has stopped answering, typically after a failed resume.
   After three unanswered checks the watchdog detaches the driver, so that case 1 re-attaches and
   re-initialises the pad when it comes back.
3. The driver is attached but there is no touchpad input device, because the pad's descriptor was
   read garbled. The watchdog detaches the driver and retries.

A check is one read of the pad's HID descriptor at I2C address `0x38`.

**The ACPI table** fixes boots where the touchpad does not exist at all. The BIOS picks the
touchpad model at power-on. If the pad does not answer at that moment, the BIOS falls back to a
generic entry whose resource method indexes past the end of a table (`AE_AML_PACKAGE_LIMIT`), so
Linux gets no I2C address or interrupt for it. The table in `acpi/ssdt-loq-touchpad.dsl` adds a
second device with the same resources the BIOS uses for the FocalTech pad, so the driver can bind
regardless. On boots where the BIOS did detect the pad, the extra device is rejected as a
duplicate address, which is expected and harmless.

## Limits and side effects

- The scripts are specific to this model: the ACPI id `FTCS0038`, I2C address `0x38`, PCI device
  `0000:00:15.0` and interrupt pin are hard-coded.
- Resetting the I2C controller prints one harmless `sysfs: cannot create duplicate filename`
  trace in the kernel log.
- `install.sh` rebuilds the initramfs of the running kernel only. Older kernels keep their
  untouched initramfs and remain a fallback in the boot menu.
- `touchpad-fix status` uses `sudo` to ask the pad directly. Without passwordless sudo it falls
  back to checking only that the driver and input device exist.
