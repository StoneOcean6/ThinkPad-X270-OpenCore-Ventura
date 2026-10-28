# Lenovo ThinkPad X270 – OpenCore EFI for macOS Ventura

A working OpenCore EFI for the **Core i5-7200U ThinkPad X270** running **macOS Ventura 13.7.8**, with notes on every fix that went into it.

> ⚠️ **Before you boot with this EFI, generate your own SMBIOS** (see [Before you use it](#before-you-use-it)). The serial numbers in `config.plist` are placeholders, and macOS/iCloud will not work properly until you replace them.

> 📌 I'm not accepting pull requests; feel free to fork.

## The story

I spent weeks trying to get macOS running properly on this X270 using premade EFI but no result and eventually end up making my own. Ventura did boot, but the list of broken things never got shorter:
- HDMI didn't work
- the trackpad froze after pressing Fn keys, and the cursor jumped after a click-drag
- Bluetooth was dead
- the trackpad died after sleep, and the power-button light kept "breathing" after wake
- the battery sat at 100% for ages
- the headset sounded muffled

Every fix I tried either did nothing or broke something else.

Eventually I got fed up and tried something different: I worked through it step by step with **Claude**. For each problem:
- pulled the actual logs (`pmset -g log`, `ioreg`, `log show`) and looked at what macOS reported
- checked the X270's ACPI tables
- compared against the kext documentation

Then made **one change per reboot**, with a config backup before each one, so a bad change was always easy to undo. Along the way i found that:
- HDMI was blocked by leftover connector patches
- the trackpad needed VoodooPS2Trackpad *enabled* (the opposite of most guides)
- the USB-C controller (XDCI) was waking the laptop seconds after it went to sleep
- macOS never resets the ThinkPad's wake LED (LED was breathing even after laptop fully wake up)
- only the internal battery was being read (i have both internal and external batteries attached)


Within a day everything on my list worked. This repo is the result. I hope it saves the next X270 owner those weeks.

## Hardware (tested configuration)

This EFI was built and tested on exactly this hardware. Other X270 configurations, such as a different Wi-Fi card, a different touchpad vendor or a different BIOS, may need changes.

| Component | Hardware | ID | macOS driver | Status |
|---|---|---|---|---|
| CPU | Intel Core i5-7200U (Kaby Lake, 2C/4T) | | XCPM via SSDT-PLUG | ✅ |
| iGPU | Intel HD Graphics 620 | 8086:5916 | WhateverGreen, `ig-platform-id` 0x591B0000, `device-id` 0x5916 | ✅ hardware acceleration, Metal 3, 1536 MB |
| Audio codec | Realtek ALC298 | 10EC:0298 rev 0x100103 | AppleALC, `alcid=29` | ✅ speakers, combo jack, both mics |
| HDMI | HDMI port on the iGPU | | WhateverGreen, stock connectors + `igfxonln=1` | ✅ tested with an HDMI→HDMI, HDMI→VGA converter |
| Wi-Fi | Intel Dual Band Wireless-AC 8265 (8265NGW, M.2) | | AirportItlwm v2.3.0, Ventura build | ✅ native menu, iMessage OK |
| Bluetooth | Intel 8265 Bluetooth (on the Wi-Fi card) | USB 8087:0A2B (port HS07) | IntelBluetoothFirmware 2.4.0 + IntelBTPatcher 2.4.0 + BlueToolFixup 2.7.2 | ✅ |
| Touchpad + TrackPoint | Synaptics, SMBus/RMI4 capable | | VoodooRMI 1.4.3 + VoodooSMBus 3.0 + VoodooPS2 2.3.7 | ✅ gestures, TrackPoint (ThinkPad nipple), buttons |
| Keyboard | ThinkPad PS/2 keyboard | | VoodooPS2Keyboard + BrightnessKeys | ✅ Fn keys |
| Battery | Internal + external (Power Bridge) | ACPI BAT0 + BAT1 | SMCBatteryManager + ECEnabler + SSDT-BATX | ✅ combined %, charging |
| SSD | NVMe 256 GB (LENSE30256GMSP340) | | native + NVMeFix | ✅ |
| Webcam | Integrated Camera (Chicony) | USB 04F2:B5AB | native | ✅ |
| USB | Sunrise Point-LP xHCI, USB-A + USB-C | | USBToolBox + UTBMap-X270 | ✅ |
| Ethernet | Intel I219 | | IntelMausi | ⚪ not tested |
| SD card reader | Realtek RTS522A | | none | ❌ not included |
| Fingerprint | Validity/Synaptics | USB 138A:0097 | none | ❌ no driver |

**Firmware/software:** OpenCore 1.0.7 · Lilu 1.7.2 · VirtualSMC · macOS Ventura 13.7.8 · SMBIOS MacBookPro14,1

## Features

### ✅ Works
- **Wi-Fi** in the native menu.
- **Apple ID services**: iMessage, FaceTime, iCloud, App Store, Apple Music.
- **Bluetooth**: headsets, mice, speakers, iPhone pairing. It survives sleep.
- **Video calls** (Zoom, Meet, Teams): camera, mics, speakers.
- **Headset**: a clear sound and its mic, with automatic switching.
- **External display** over HDMI.
- **Trackpad and TrackPoint**: gestures, and no freeze after Fn keys.
- **Keyboard**: Fn keys for brightness, volume, mute and mic mute.
- **Battery**: both batteries combined (correct % and time remaining), charging, Low Power Mode.
- **Sleep and wake** via the lid: the trackpad and the "i" LED come back.
- **Graphics acceleration** (Metal 3), USB-A/USB-C, CPU power management.
- **Streaming in Chrome/Edge/Firefox**: Netflix, Prime, Disney+, Apple TV+ (tv.apple.com), YouTube, Spotify.

### ❌ Doesn't work / limits
- **AirDrop, Handoff, Universal Clipboard, Continuity Camera, Sidecar, Universal Control, Apple Watch unlock, Apple Pay**: limits of the Intel Wi-Fi card.
- **FairPlay video in Safari and the Apple TV app**: needs an AMD GPU on macOS 11+ ([WhateverGreen DRM chart](https://github.com/acidanthera/WhateverGreen/blob/master/Manual/FAQ.Chart.md)). Use Chrome/Edge.
- **Fingerprint reader and SD card reader.**
- **Waking from a USB mouse or keyboard**: disabled on purpose by the GPRW fix. Use the lid, a key or the power button.
- **Hibernation**: disabled on purpose. Find My Mac doesn't work while asleep (tcpkeepalive off).
- **Going to sleep takes ~15–30 s**, because of the Wi-Fi driver plus Apple's push service. It's harmless.
- **macOS Sonoma or newer**: the Wi-Fi kext here is the Ventura build.

### 📱 Phone connectivity

**iPhone** (same Apple ID on both):

| Feature | Status |
|---|---|
| iMessage, FaceTime | ✅ |
| SMS on the Mac (Text Message Forwarding) | ✅ |
| iCloud Photos / Drive / Notes / Reminders / Calendar / Contacts / Keychain / Safari tabs | ✅ |
| Find My (locate the iPhone from the Mac) | ✅ |
| USB: Finder backup/sync, photo import, USB tethering | ✅ |
| Personal Hotspot (joined as a Wi-Fi network) | ✅ |
| Bluetooth audio / AirPods | ✅ (automatic switching ⚠️) |
| Phone calls through the iPhone | ⚠️ hit or miss |
| Instant Hotspot | ⚠️ unreliable |
| iPhone notifications on the Mac (a macOS 15 feature) | ❌. Use the Mac versions of your messaging apps |
| AirDrop, Handoff, Universal Clipboard, Continuity Camera, iPhone Mirroring, Apple Pay | ❌ |

**Android:** no native integration. These free apps fill the gaps:
- **LocalSend**: AirDrop-style wireless sharing; it also works with an iPhone.
- **OpenMTP**: USB file transfer.
- **KDE Connect**: notifications and a shared clipboard.
- **WhatsApp Desktop**, or messages.google.com for SMS.

## Before you use it

1. **Generate your own SMBIOS** for `MacBookPro14,1` with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS), then fill in `PlatformInfo → Generic`:
   - `SystemSerialNumber`, `MLB`, `SystemUUID`: currently placeholders
   - `ROM`: currently zeros. Use your network card's MAC address or a random 6-byte value.

   Check the serial at Apple's coverage page; it should say **not valid**.
2. **The USB map (`UTBMap-X270.kext`) is for the X270.** Make your own with USBToolBox if your ports differ.
3. **itlwm.kext is included but disabled** (for installs only). If you need it, put your network name and password in `itlwm.kext/Contents/Info.plist → WiFiConfig`.
4. **Apply the sleep settings once:**
   ```bash
   sudo pmset -a hibernatemode 0 standby 0 autopoweroff 0 powernap 0 proximitywake 0 tcpkeepalive 0
   ```
5. **Turn off "Install macOS updates"** in Software Update, so you don't end up on Sonoma.
6. **Remove `-v keepsyms=1 debug=0x100`** from `boot-args` once everything works, for an Apple-logo boot.
7. **BIOS:** follow the [Dortania Kaby Lake laptop guide](https://dortania.github.io/OpenCore-Install-Guide/config-laptop.plist/kaby-lake.html).

## Fixes beyond a standard Dortania EFI

| Problem | Fix |
|---|---|
| HDMI not detected | Removed custom connector patches (`framebuffer-con1/2-*`, `portcount`); stock `0x591B0000` connectors + `igfxonln=1` |
| Trackpad dead with VoodooRMI | **Keep VoodooPS2Trackpad enabled** (VoodooPS2 ≥2.2 + VoodooRMI ≥1.3); disable only VoodooPS2Mouse and PS2's VoodooInput |
| Bluetooth `Address: NULL` on 13.4+ | BlueToolFixup ≥2.6.7 + NVRAM `bluetoothExternalDongleFailed` / `bluetoothInternalControllerInfo` |
| Dark wake `due to XDCI`; trackpad dead and LED breathing after wake | `SSDT-GPRW` + rename `GPRW→XPRW`, plus the pmset settings above |
| "i" LED keeps breathing after wake | Custom [`SSDT-WAKLED`](ACPI-source/SSDT-WAKLED.dsl) + rename `_WAK→ZWAK` |
| Only the internal battery reported | [`SSDT-BATX`](ACPI-source/SSDT-BATX.dsl) + `Notify(BAT0/BAT1)→BATX` renames |
| Muffled headset | AppleALC layout 29 instead of 22 |

Full details, with the reasoning and how each fix was verified: **[docs/CHANGELOG.md](docs/CHANGELOG.md)**. Do's and don'ts: **[docs/WHAT-WORKS.md](docs/WHAT-WORKS.md)**.

## Repository layout

```
EFI/                 the OpenCore EFI (copy to your EFI partition)
ACPI-source/         .dsl sources of the added SSDTs
docs/CHANGELOG.md    every change, with the reasoning and how it was verified
docs/WHAT-WORKS.md   features, limits, do's and don'ts
```

## Credits

- [Acidanthera](https://github.com/acidanthera): OpenCore, Lilu, VirtualSMC, WhateverGreen, AppleALC, VoodooPS2, BrcmPatchRAM/BlueToolFixup, ECEnabler, NVMeFix, RestrictEvents, BrightnessKeys
- [OpenIntelWireless](https://github.com/OpenIntelWireless): itlwm / AirportItlwm, IntelBluetoothFirmware
- [VoodooSMBus](https://github.com/VoodooSMBus): VoodooRMI, VoodooSMBus
- [USBToolBox](https://github.com/USBToolBox)
- [Dortania](https://dortania.github.io): guides, SSDT-PLUG / EC-USBX / PNLF / XOSI / GPRW
- [benbender](https://github.com/benbender/x1c6-hackintosh): SSDT-BATX
- [nicktimur/Lenovo-X270-Hackintosh-OpenCore-Sonoma](https://github.com/nicktimur/Lenovo-X270-Hackintosh-OpenCore-Sonoma): reference for the X270 graphics setup
- [Claude](https://claude.ai) by Anthropic: troubleshooting 

## Licenses

This repo bundles work from many projects. **Each component keeps its own license**, and the full source code is available at the links below. The kexts and OpenCore binaries come from the projects' releases and haven't been modified here. The one exception is `itlwm.kext/Contents/Info.plist`, where the saved Wi-Fi entries were cleared.

| Component | License | Source |
|---|---|---|
| OpenCore (OpenCore.efi, BOOTx64.efi, OpenRuntime.efi, OpenShell.efi) | BSD-3-Clause | [acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) |
| HfsPlus.efi | Apple proprietary driver, distributed via OcBinaryData | [acidanthera/OcBinaryData](https://github.com/acidanthera/OcBinaryData) |
| Lilu | BSD-3-Clause | [acidanthera/Lilu](https://github.com/acidanthera/Lilu) |
| VirtualSMC + plugins (SMCBatteryManager, SMCProcessor, SMCSuperIO, SMCLightSensor, SMCDellSensors) | BSD-3-Clause | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) |
| WhateverGreen | BSD-3-Clause | [acidanthera/WhateverGreen](https://github.com/acidanthera/WhateverGreen) |
| AppleALC | BSD-3-Clause | [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC) |
| NVMeFix | BSD-3-Clause | [acidanthera/NVMeFix](https://github.com/acidanthera/NVMeFix) |
| RestrictEvents | BSD-3-Clause | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents) |
| HibernationFixup | BSD-3-Clause | [acidanthera/HibernationFixup](https://github.com/acidanthera/HibernationFixup) |
| CPUFriend | BSD-3-Clause | [acidanthera/CPUFriend](https://github.com/acidanthera/CPUFriend) |
| BrightnessKeys | BSD-3-Clause | [acidanthera/BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) |
| VoodooPS2Controller (+ Keyboard, Mouse, Trackpad, VoodooInput) | Apple Public Source License 2.0 | [acidanthera/VoodooPS2](https://github.com/acidanthera/VoodooPS2) |
| ACPIBatteryManager (disabled) | Apple Public Source License 2.0 | [RehabMan/OS-X-ACPI-Battery-Driver](https://github.com/RehabMan/OS-X-ACPI-Battery-Driver) |
| BlueToolFixup, BrcmPatchRAM3, BrcmFirmwareData | GPL-2.0 | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) |
| IntelMausi | GPL-2.0 | [acidanthera/IntelMausi](https://github.com/acidanthera/IntelMausi) |
| AirportItlwm, itlwm | GPL-2.0 | [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm) |
| IntelBluetoothFirmware, IntelBTPatcher | GPL-3.0 | [OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware) |
| VoodooRMI (+ RMISMBus, RMII2C, VoodooInput) | GPL-2.0 | [VoodooSMBus/VoodooRMI](https://github.com/VoodooSMBus/VoodooRMI) |
| VoodooSMBus | GPL-2.0 | [VoodooSMBus/VoodooSMBus](https://github.com/VoodooSMBus/VoodooSMBus) |
| ECEnabler | no license file published; © 1Revenger1 | [1Revenger1/ECEnabler](https://github.com/1Revenger1/ECEnabler) |
| USBToolBox kext | no license file published; © USBToolBox | [USBToolBox/kext](https://github.com/USBToolBox/kext) |
| AppleMCEReporterDisabler (plist-only kext) | © 2019 XLNC | |
| SSDT-PLUG-DRTNIA, SSDT-EC-USBX-LAPTOP, SSDT-PNLF, SSDT-XOSI, SSDT-GPRW | from Dortania's guides (CC BY-NC-SA 4.0) | [Dortania](https://dortania.github.io) |
| SSDT-BATX | "Copyleft (c) 2020 by bb. No rights reserved." (repo: MIT) | [benbender/x1c6-hackintosh](https://github.com/benbender/x1c6-hackintosh) |

**My own work** (`config.plist`, `SSDT-WAKLED`, the `UTBMap-X270` USB map and the docs) is free to use, modify and share. Credit is appreciated but not required.

Use at your own risk. Not affiliated with Apple or Lenovo.
