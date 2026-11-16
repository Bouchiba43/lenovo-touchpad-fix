/*
 * SSDT fix-up for Lenovo LOQ 15IAX9 (83GS) BIOS NECN50WW, FocalTech FTCS0038 touchpad.
 *
 * Problem: the DSDT device \_SB.PC00.I2C0.TPAD chooses the touchpad model from a
 * table using the BIOS POST-time detection byte TPDF. When the BIOS fails to detect
 * the touchpad at POST, TPDF matches nothing, TPAD._HID returns the generic
 * "MSFT0001" and TPAD._CRS indexes past the end of the table
 * (AE_AML_PACKAGE_LIMIT), so Linux never gets the I2C address/IRQ and the
 * touchpad is absent for the whole boot even though the hardware answers at 0x38.
 *
 * This table adds a sibling device with the exact resources the DSDT uses for the
 * FocalTech entry (I2C address 0x38 on \_SB.PC00.I2C0, GpioInt pin 455 on \_SB.GPI0,
 * HID descriptor register 0x0001), so i2c-hid can bind regardless of TPDF.
 *
 * Bus speed: 400 kHz, identical to the DSDT. (A 100 kHz test on 2026-10-06 did not reduce the
 * lost-arbitration/timeout bursts, so the original speed is kept. The Linux DesignWare
 * driver uses the lowest speed requested by any client on the bus, so a lower value
 * here would apply to every boot. Change the speed in I2cSerialBusV2 below,
 * recompile with iasl -tc, copy the .aml to /etc/acpi-override and run dracut -f.
 */
DefinitionBlock ("", "SSDT", 2, "LOQFIX", "TPADFIX", 0x00000001)
{
    External (\_SB.PC00.I2C0, DeviceObj)
    External (\_SB.GPI0, DeviceObj)

    Scope (\_SB.PC00.I2C0)
    {
        Device (TPDX)
        {
            Name (_HID, "FTCS0038")  // FocalTech, same as DSDT table entry
            Name (_CID, "PNP0C50")   // HID-over-I2C compatible ID
            Name (_UID, 0x02)
            Name (_S0W, 0x03)
            Name (_DDN, "FocalTech FTCS0038 touchpad (SSDT fix-up)")

            Name (_CRS, ResourceTemplate ()
            {
                I2cSerialBusV2 (0x0038, ControllerInitiated, 400000,
                    AddressingMode7Bit, "\\_SB.PC00.I2C0",
                    0x00, ResourceConsumer, , Exclusive,
                    )
                GpioInt (Level, ActiveLow, ExclusiveAndWake, PullUp, 0x0000,
                    "\\_SB.GPI0", 0x00, ResourceConsumer, ,
                    )
                    {   // Pin list
                        0x01C7
                    }
            })

            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Method (_DSM, 4, Serialized)
            {
                // HID I2C device _DSM, UUID 3cdff6f7-4267-4555-ad05-b30a3d8938de
                If ((Arg0 == ToUUID ("3cdff6f7-4267-4555-ad05-b30a3d8938de")))
                {
                    If ((Arg2 == Zero))
                    {
                        If ((Arg1 == One))
                        {
                            Return (Buffer (One) { 0x03 })
                        }
                        Return (Buffer (One) { 0x00 })
                    }
                    If ((Arg2 == One))
                    {
                        Return (One)   // HID descriptor address 0x0001 (DSDT TPID[FocalTech][2])
                    }
                }
                Return (Buffer (One) { 0x00 })
            }
        }
    }
}
