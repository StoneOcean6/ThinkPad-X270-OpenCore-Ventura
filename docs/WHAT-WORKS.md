# What works, what doesn't, and the rules

macOS Ventura 13.7.8 · OpenCore 1.0.7. Technical details are in [CHANGELOG.md](CHANGELOG.md).

## Works
- **Wi-Fi** in the normal menu bar (AirportItlwm).
- **Apple ID services**: iMessage, FaceTime, iCloud, App Store (after you generate your own SMBIOS).
- **Bluetooth**: headsets, mice, speakers, iPhone pairing. It keeps working after sleep.
- **Video calls** (Zoom, Meet, Teams): camera, built-in mic, speakers.
- **Headset**: a clear sound and its mic (audio layout 29). Sound switches automatically when you plug it in or out.
- **External monitor** over HDMI, including through an HDMI→VGA converter.
- **Trackpad** (VoodooRMI) with gestures. The TrackPoint and its buttons work too, with no freeze after Fn keys.
- **Keyboard**: Fn keys for brightness, volume, mute and mic mute.
- **Battery**: both batteries are counted together, with a correct % and time remaining. Charging shows correctly.
- **Sleep**: closing the lid sleeps, and opening it wakes the laptop. The trackpad and the "i" LED come back normally.
- **USB**: USB-A and USB-C.
- **Graphics acceleration**: Metal 3.
- **CPU power management**: XCPM, and Low Power Mode works.

## Doesn't work, or works with limits
- **AirDrop**: needs a Broadcom Wi-Fi card swap; not possible with the Intel 8265.
- **Handoff, Universal Clipboard, Continuity Camera, wireless Sidecar**: disabled by the Intel Wi-Fi driver on Ventura.
- **Fingerprint reader**: no macOS driver exists.
- **SD card reader**: not included (RealtekCardReader is beta).
- **Waking from a USB mouse or keyboard**: off on purpose (the GPRW sleep fix). Use the lid, a key or the power button.
- **Android phone file transfer**: macOS has no MTP. Use OpenMTP.
- **Find My Mac while asleep**: TCP keep-alive is off for clean sleep. It works while awake.
- **Hibernation / deep standby**: off on purpose. It caused wake problems.
- **Going to sleep takes 15–30 s**, with the fan running. That's the Wi-Fi driver plus Apple's push service; it's harmless.

## DRM content (streaming video and music)
Since macOS 11, FairPlay video on a hackintosh needs a supported AMD GPU. Intel-graphics-only machines can't decode it. Source: the [WhateverGreen DRM chart](https://github.com/acidanthera/WhateverGreen/blob/master/Manual/FAQ.Chart.md).
- **Works**
  - **Netflix, Prime Video, Disney+, HBO Max and similar in Chrome, Edge or Firefox** (Widevine, which doesn't need the GPU). Expect up to roughly 720p–1080p depending on the service.
  - **Apple TV+ in Chrome** at tv.apple.com.
  - YouTube, Twitch, and normal web video.
  - **Music**: Apple Music in the Music app (including lossless), Spotify, YouTube Music.
  - Local video files.
- **Doesn't work** (black screen or an error):
  - the same services **in Safari**
  - movies and shows in the **Apple TV app**

## Do
1. **Keep rescue USB sticks unplugged for normal use.** The BIOS boots from USB first.
2. **Back up `config.plist` before every EFI change**, and make one change per reboot.
3. **After any macOS security update**, check Wi-Fi, Bluetooth, the trackpad, audio and sleep.
4. **Keep a working copy of the EFI on a USB stick** as a rescue boot.

## Don't
1. **Don't upgrade to Sonoma or newer** with this EFI. The Wi-Fi kext is the Ventura build, and other kexts and patches would need updating. Turn off "Install macOS updates" in Software Update.
2. **Don't switch VoodooPS2Trackpad off.** The trackpad dies without it, even with VoodooRMI.
3. **Don't reset the sleep settings** (`pmset restoredefaults`). If it happens, re-run:
   ```
   sudo pmset -a hibernatemode 0 standby 0 autopoweroff 0 powernap 0 proximitywake 0 tcpkeepalive 0
   ```
4. **Don't update kexts at random.** Update Lilu-based kexts together, with a backup first.
5. **Check before a Lenovo BIOS update.** A new BIOS can change the ACPI tables that the sleep, LED and battery patches rely on.
6. **Don't turn on FileVault** unless OpenCore is set up for it.

## If it won't boot
1. Boot from your rescue USB stick (a copy of a working EFI).
2. Mount the internal EFI (`sudo diskutil mount disk0s1`) and restore your last good `config.plist` backup.
3. Unplug the stick and reboot.
