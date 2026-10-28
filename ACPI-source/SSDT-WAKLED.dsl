/*
 * ThinkPad X270: restore the power-button / lid "i" LED after wake on macOS.
 * Pair with ACPI patch: rename Method(_WAK,1,Serialized) _WAK -> ZWAK
 *   Find 5F57414B09  Replace 5A57414B09
 * Does what _SI._SST(1) does for LEDs 0x00, 0x0A, 0x07, without the beep.
 * No _OSI check: setting the LEDs to "working" after wake is what every OS does anyway.
 */
DefinitionBlock ("", "SSDT", 2, "HACK", "WAKLED", 0x00000000)
{
    External (ZWAK, MethodObj)
    External (_SB_.PCI0.LPCB.EC__.LED_, MethodObj)

    Method (_WAK, 1, Serialized)
    {
        Local0 = ZWAK (Arg0)
        If (CondRefOf (\_SB.PCI0.LPCB.EC.LED))
        {
            \_SB.PCI0.LPCB.EC.LED (Zero, 0x80)
            \_SB.PCI0.LPCB.EC.LED (0x0A, 0x80)
            \_SB.PCI0.LPCB.EC.LED (0x07, Zero)
        }
        Return (Local0)
    }
}
