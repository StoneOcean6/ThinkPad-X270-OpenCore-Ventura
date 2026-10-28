# Changelog

macOS Ventura 13.7.8 · OpenCore 1.0.7 · Lilu 1.7.2 · SMBIOS MacBookPro14,1

This lists the changes made to a previously "mostly working" X270 EFI, with the reason for each one and how it was verified. Each change was done on its own reboot, with a `config.plist` backup before it.

## Tips for editing this config from Terminal
- Mount the EFI: `sudo diskutil mount disk0s1`. Unmount it when you're done: `sudo diskutil unmount disk0s1`.
- Back up before every change:
  ```
  mkdir -p ~/EFI-backups && cp /Volumes/EFI/EFI/OC/config.plist ~/EFI-backups/config-$(date +%Y%m%d-%H%M).plist
  ```
- **If the BIOS finds a USB stick with an EFI on it, it boots from that first.** Unplug rescue sticks during testing, or your edits to the internal EFI won't take effect.
- zsh doesn't treat `#` as a comment when you paste, so leave comments out of pasted command blocks. A trailing `\` makes the shell wait for more input.
- In zsh, write `${VAR}:key`, not `$VAR:key`. A colon after a variable is read as a modifier, so `$i:Path` becomes a filesystem path.
- PlistBuddy can't write hex data. Use `plutil -insert <keypath> -data <base64>` instead.
- ioreg shows USB vendor/product IDs in decimal (Intel 0x8087 = 32903).
- OpenCore applies ACPI→Patch **before** ACPI→Add, so renames such as `_OSI`→`XOSI` don't touch the SSDTs you add.

## Changes

### 1. boot-args
Added `igfxonln=1`. Current boot-args: `-v keepsyms=1 debug=0x100 alcid=29 igfxonln=1`. `boot-args` is in NVRAM → Delete, so OpenCore rewrites it on every boot.

### 2. Wi-Fi: AirportItlwm v2.3.0, Ventura build
- Kernel→Add 6 (AirportItlwm) is enabled; 7 (itlwm) is disabled but kept for installs.
- Native Wi-Fi menu. iMessage works too, so NullEthernet isn't needed.

### 3. HDMI
- Problem: an external display was never detected, even with `igfxonln=1`.
- Cause: the config enabled only 2 connectors (`framebuffer-portcount` = 2), disabled connector 2 (`framebuffer-con2-index` = FFFFFFFF), and forced connector 1 to HDMI.
- Fix: removed `framebuffer-con1-enable`, `framebuffer-con1-type`, `framebuffer-con2-enable`, `framebuffer-con2-index` and `framebuffer-portcount` from DeviceProperties `PciRoot(0x0)/Pci(0x2,0x0)`. The stock connectors of `0x591B0000` work, as in other X270 EFIs.
- Remaining keys: `AAPL,ig-platform-id` 00001B59, `device-id` 16590000, `enable-hdmi20`, `framebuffer-fbmem` 00009000, `framebuffer-patch-enable`, `framebuffer-stolenmem` 00003001. `hda-gfx` = onboard-1 is injected automatically.
- Tested working, including through an HDMI→VGA converter.

### 4. Trackpad: VoodooRMI + VoodooSMBus
- Problem: with VoodooPS2 alone, the trackpad froze after Fn-key presses and the cursor jumped after click-drag.
- The X270's touchpad is Synaptics; under PS2 it shows as `ApplePS2SynapticsTouchPad`, and it supports SMBus.
- Kernel→Add order:
  - 16 VoodooPS2Controller: **on**
  - 17 VoodooPS2's VoodooInput: **off**
  - 18 VoodooPS2Keyboard: **on**
  - 19 VoodooPS2Mouse: **off**
  - 20 VoodooPS2Trackpad: **on**
  - 21 VoodooSMBus (3.0): **on**
  - 22 VoodooRMI (1.4.3): **on**
  - 23 RMISMBus: **on**
  - 24 VoodooRMI's VoodooInput: **on**
- **Important:** older guides say to disable VoodooPS2Trackpad. With Acidanthera VoodooPS2 ≥2.2 and VoodooRMI ≥1.3 it must stay **enabled**. With it disabled, RMISMBus never attaches and the trackpad is dead.
- Verify: `ioreg -w0 | grep -o -E '\+-o (RMISMBus|RMIBus)'` lists both.

### 5. Bluetooth (Intel 8265, USB 8087:0A2B on HS07)
- Enabled IntelBluetoothFirmware 2.4.0, IntelBTPatcher 2.4.0 and BlueToolFixup. Brcm kexts stay off.
- Problem: `Address: NULL` on macOS 13.7.8, because BlueToolFixup 2.6.1 is too old for 13.4+.
- Fix: BlueToolFixup **2.7.2**, plus these in NVRAM→Add `7C436110-AB2A-4BBB-A880-FE41995C9F82`:
  - `bluetoothExternalDongleFailed` = `00`
  - `bluetoothInternalControllerInfo` = 14 × `00`
  
  Both are also listed in NVRAM→Delete.
- Result: Chipset THIRD_PARTY_DONGLE, State On. It survives sleep.

### 6. Sleep settings (pmset, not EFI)
```
sudo pmset -a hibernatemode 0 standby 0 autopoweroff 0 powernap 0 proximitywake 0 tcpkeepalive 0
```
Hibernation, standby and Power Nap dark wakes caused half-finished wakes. Undo with `sudo pmset -a restoredefaults`.

### 7. Sleep: XDCI dark wakes (SSDT-GPRW)
- Symptom: `DarkWake from Normal Sleep … due to XDCI` about 16 s after sleep. Opening the lid during that dark wake turned it into a full wake, but the trackpad stayed dead and the "i" LED kept breathing.
- The X270 DSDT has `Method (GPRW, 2)` in `Scope (\)`, and XHC/XDCI/GLAN/HDAS use GPE 0x6D.
- Fix: ACPI→Add `SSDT-GPRW.aml` (Dortania) plus ACPI→Patch "GPRW to XPRW" (Find `4750525702`, Replace `5850525702`).
- Effect: GPE 0x6D can't wake the laptop from S3. The lid, keyboard and power button still wake it; a USB mouse/keyboard doesn't.
- Result: no more XDCI dark wakes, and the trackpad works after every wake.
- Note: going to sleep takes about 15–20 s (apsd up to 28 s, AirportItlwm's en0 5.3 s). It's harmless.

### 8. Breathing "i" LED after wake (custom SSDT-WAKLED)
- Cause: on wake, Windows calls `\_SI._SST(1)`, which sets the EC LEDs back to "working". macOS never calls it, so the LEDs keep the sleep pattern.
- Fix: ACPI→Add `SSDT-WAKLED.aml` ([source](../ACPI-source/SSDT-WAKLED.dsl)). It defines `_WAK`, which calls the original (renamed `ZWAK`) and then `\_SB.PCI0.LPCB.EC.LED(0,0x80)`, `(0x0A,0x80)` and `(0x07,0)`. That's the LED part of `_SST(1)`, without the beep.
- ACPI→Patch "_WAK to ZWAK": Find `5F57414B09`, Replace `5A57414B09`. The X270's `_WAK` is `Method(_WAK,1,Serialized)`, and the pattern occurs once in the DSDT.
- Result: the LED goes solid after wake.

### 9. Headset audio: layout 29
- The codec is Realtek ALC298 (`0x10ec0298`). Layout 22 (Razer Blade 14) gave a muffled headset. Layout **29** ("ALC298 for Lenovo X270") is clear on the speakers, the headset and both mics, and switching works.
- Verify: `ioreg -lw0 | grep -m1 '"alc-layout-id"'` should show `<1d000000>`.

### 10. Dual battery (SSDT-BATX)
- Problem: only the internal battery was reported (Max 1670 / Design 2059 mAh). Because the X270 drains the external battery first, macOS showed ~100% until the external one was empty.
- Fix: ACPI→Add `SSDT-BATX.aml` (benbender, rev 10, [source](../ACPI-source/SSDT-BATX.dsl)), plus two DSDT-only renames (TableSignature `DSDT`):
  - `Notify(BAT0…)` → `BATX`: Find `86 42 41 54 30`, Replace `86 42 41 54 58`
  - `Notify(BAT1…)` → `BATX`: Find `86 42 41 54 31`, Replace `86 42 41 54 58`
- The X270 DSDT has `\_SB.PCI0.LPCB.EC.BAT0/BAT1` with `Name(_HID)`, `HIID` and `H8DR`, as BATX expects.
- Result: both batteries are combined (e.g. Max 5546 / Design 6396 mAh), the % and time remaining are correct, charging shows, and it survives sleep.
- Known: two `ACPI Exception: AE_BAD_PARAMETER` lines are logged right after the _BATX table loads. No visible effect.

## Not included
- **SD card reader (RTS522A):** RealtekCardReader v0.9.7 + RealtekCardReaderFriend v1.0.4 would be the drivers (after Lilu, driver before Friend). They're beta and officially tested only up to Monterey, and RTS5227-family readers have known timeouts on T440/T450.
- **Fingerprint reader (138A:0097):** no macOS driver.
- **AirDrop / Handoff** with the Intel card.
