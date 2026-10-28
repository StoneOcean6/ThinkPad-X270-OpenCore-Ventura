# Troubleshooting: problems found after daily use

These came up after the EFI was finished and published, during normal day-to-day use. Each entry gives the symptom, what the logs showed, the fix, and its current status.

| # | Problem | Status |
|---|---|---|
| 1 | [Trackpad dead after a self-triggered "notification wake"](#1-trackpad-dead-after-a-self-triggered-notification-wake) | 🟡 fix applied, being tested |
| 2 | [WhatsApp (Mac App Store) won't reconnect after sleep](#2-whatsapp-mac-app-store-wont-reconnect-after-sleep) | 🔴 under investigation, workaround available |
| 3 | [Dock magnification doesn't work](#3-dock-magnification-doesnt-work) | ✅ solved (not a hackintosh issue) |

---

## 1. Trackpad dead after a self-triggered "notification wake"

**Symptom**
- After some sleeps, the trackpad doesn't respond on wake. The keyboard works.
- Putting the laptop to sleep again and waking it brings the trackpad back.

**What the logs showed**
- `RMISMBus` and `RMIBus` were still attached (`ioreg`), so VoodooRMI hadn't crashed. The laptop had also booted from the correct EFI.
- `pmset -g log`:
  - Shortly before the bad wake: `Entering DarkWake state due to 'Notification Wake Back to Sleep'`. macOS had woken itself to show an alert, then gone back to sleep.
  - `Dark Wake Count in this sleep cycle: 3`.
  - **Every good wake** lists `ApplePS2Controller driver is slow(msg: SetState to 2)` in its wake notifications. **The bad wake is the only one without it**: the PS2/trackpad controller never went through a proper wake.
- `pmset -g sched` showed "user-visible" scheduled wakes:
  - `com.apple.alarm.user-visible-com.apple.CalendarNotification.EKTravelEngine.periodicRefreshTimer`: Calendar's **"Time to leave"** travel-time alerts
  - `com.apple.alarm.user-visible-com.apple.acmd.alarm`: another Apple system alarm

**Cause (likely):** macOS wakes the laptop by itself to show alerts. That partial wake doesn't take the PS2 controller through its normal wake path, and the next real wake inherits a dead trackpad. This is the same kind of problem as the XDCI dark wakes fixed in the [changelog](CHANGELOG.md), but triggered by notifications instead of the USB controller.

**Fix (no EFI changes)**
1. Calendar → Settings → Alerts → untick **"Time to leave"**.
2. System Settings → Notifications → turn off **"Allow notifications when the display is sleeping"**. Notifications still show as soon as you wake the laptop.
3. Check that the scheduled list has shrunk with `pmset -g sched`.

**Workaround if it happens:** close the lid, wait about 10 seconds, and open it again.

**If it still happens**, run this before you sleep it again, to see what woke the laptop:
```bash
pmset -g log | grep -E 'DarkWake from|Notification|due to' | tail -20
```

> Avoid the "Disable RTC wake scheduling" kernel patch for this. It would also break alarms and scheduled tasks.

---

## 2. WhatsApp (Mac App Store) won't reconnect after sleep

**Symptom**
- After waking, WhatsApp stays on "Connecting…".
- Waiting, turning Wi-Fi off and on, or quitting and reopening WhatsApp (⌘Q) doesn't help.
- **A full restart of the laptop fixes it.**

**What was ruled out**
- The network itself: `scutil --nwi` shows Wi-Fi (`en1`) reachable on IPv4 and IPv6, and `curl -4` / `curl -6` to `https://web.whatsapp.com` both return `200`.
- Safari and iMessage work normally after wake.
- `tcpkeepalive` stays **off** on purpose: turning it on brings back background wakes.

**Theory:** the App Store version of WhatsApp is built on Apple's networking framework and checks whether macOS says the network is usable before it tries to connect. Something that WhatsApp depends on (but Safari and iMessage don't) seems to get stuck after a wake, and only a reboot clears it. Not confirmed yet.

**Next time it happens, before restarting:**

1. Collect information (this only reads):
   ```bash
   pgrep -lf -i whatsapp
   nc -vz -G 5 g.whatsapp.net 443
   nc -vz -G 5 g.whatsapp.net 5222
   pmset -g | grep lowpowermode
   log show --last 10m --style compact --predicate 'process CONTAINS[c] "whatsapp"' | tail -40
   ```
2. Then try these one at a time, checking WhatsApp after each:
   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```
   ```bash
   killall WhatsApp; sleep 2; open -a WhatsApp
   ```
   ```bash
   sudo killall nsurlsessiond networkserviceproxy
   ```
   Whichever one works points to the stuck component. It can then be run automatically after every wake (for example with `sleepwatcher`).

**Workaround:** restart the laptop. WhatsApp Web in Chrome is also unaffected.

---

## 3. Dock magnification doesn't work

**Symptom:** hovering over the Dock never enlarges the icons, even with Magnification switched on in System Settings.

**Cause:** this isn't a hackintosh issue. It's the settings themselves:
```bash
defaults read com.apple.dock magnification   # 0   = off
defaults read com.apple.dock tilesize        # 73  = normal icon size
defaults read com.apple.dock largesize       # 16  = "magnified" size, SMALLER than the icons
```
On top of that, **System Settings was open** while the values were changed from Terminal. It still showed the old state, and touching a slider wrote the old values (`magnification 0`, `largesize 16`) back.

**Fix**
1. Quit System Settings completely with **⌘Q**.
2. Run:
   ```bash
   defaults write com.apple.dock magnification -bool true
   defaults write com.apple.dock tilesize -int 48
   defaults write com.apple.dock largesize -int 96
   killall Dock
   ```
3. When fine-tuning in System Settings → Desktop & Dock afterwards, keep the **Magnification** slider clearly to the right of the **Size** slider.

**General tip:** quit System Settings before changing settings from Terminal, or it may overwrite your change.

**Pasting tip:** paste each command on its own line. In this case one line got glued onto a leftover `killall Dock` (`killall Dock~defaults write … -bool true`), so `killall` treated `-bool` as one of its own options and the setting was never saved.
