# Troubleshooting: problems found after daily use

These came up after the EFI was finished and published, during normal day-to-day use. Each entry gives the symptom, what the logs showed, the fix, and its current status.

| # | Problem | Status |
|---|---|---|
| 1 | [Trackpad dead after a self-triggered "notification wake"](#1-trackpad-dead-after-a-self-triggered-notification-wake) | ✅ fixed with two settings (still being watched) |
| 2 | [Laptop turns itself back on right after shutdown](#2-laptop-turns-itself-back-on-right-after-shutdown) | ✅ solved (EFI fix) |
| 3 | [Slow after login, typing lag, apps slow to open](#3-slow-after-login-typing-lag-apps-slow-to-open) | 🟡 mostly solved; the drive's heat is still open |
| 4 | [WhatsApp (Mac App Store) won't reconnect after sleep](#4-whatsapp-mac-app-store-wont-reconnect-after-sleep) | 🔴 under investigation, workaround available |
| 5 | [Dock magnification doesn't work](#5-dock-magnification-doesnt-work) | ✅ solved (not a hackintosh issue) |

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

**Cause (likely):** macOS wakes the laptop by itself to show alerts. That partial wake doesn't take the PS2 controller through its normal wake path, and the next real wake inherits a dead trackpad.

**Fix (no EFI changes)**
1. Calendar → Settings → Alerts → untick **"Time to leave"**.
2. System Settings → Notifications → turn off **"Allow notifications when the display is sleeping"**. Notifications still show as soon as you wake the laptop.
3. Optional: System Settings → Battery → Options → **"Wake for network access" → Never** (`sudo pmset -a womp 0`). The Intel Wi-Fi can't wake-on-LAN anyway, so this only removes another source of self-triggered wakes.

**Result so far:** the trackpad has worked after every wake since these settings were changed.

**Workaround if it happens:** close the lid, wait about 10 seconds, and open it again. To see what woke the laptop:
```bash
pmset -g log | grep -E 'DarkWake from|Notification|due to' | tail -20
```

> Avoid the "Disable RTC wake scheduling" kernel patch for this. It would also break alarms and scheduled tasks.

---

## 2. Laptop turns itself back on right after shutdown

**Symptom:** seconds after Shut Down, the laptop powers back on. It happened on battery and on AC, with nothing plugged into USB.

**Side effect:** each interrupted shutdown counts as unclean, so the next startup does a longer disk check: more lines of verbose text and a longer wait before the login screen.

**Cause:** when macOS powers off, it doesn't tell the USB controller (XHC) to stop sending its wake signal (PME). The controller then wakes the laptop straight back up.

**Fix (EFI):** Dortania's `FixShutdown-USB-SSDT` (originally RehabMan), plus the rename `_PTS → ZPTS`, now included in this EFI. See [CHANGELOG](CHANGELOG.md#11-laptop-powering-back-on-right-after-shutdown-fixshutdown-usb-ssdt).
- Patch: Find `5F50545301` → Replace `5A50545301`, TableSignature `DSDT`. It matches only the `_PTS` method definition, which occurs once in the X270 DSDT.

**Verify:**
```bash
log show --last boot --style compact --predicate 'eventMessage CONTAINS "SSDT"' | grep ZPTS          # SSDT "Slav ZPTS" loaded
log show --last boot --style compact --predicate 'eventMessage CONTAINS "Previous shutdown cause"'  # 5 = clean shutdown
```

**Result:** it stays off after shutdown, the shutdown cause is `5` (clean), and the kernel-to-login-screen time is back to about 20 s.

---

## 3. Slow after login, typing lag, apps slow to open

**Symptom:** the first minutes after login were very slow: apps (including the Claude desktop app) took a long time to open, and at times even typing lagged. Startup up to the login screen was normal (about 20 s from kernel start to the login window).

**What the measurements showed**
- **CPU mostly idle, but a high load average** (~3.9 on a 2-core CPU). Processes were **waiting on the disk**.
- `iostat`: ~100 tiny writes per second (≈4.7 KB each).
- **The SSD itself is healthy** (`smartctl`): 10% used, 100% spare, 0 media errors, SMART PASSED; `diskutil verifyVolume disk1` → all OK.
- **But it slows down badly under many small, parallel writes.** `dd` wrote 1 GB at **10–21 MB/s** shortly after startup, versus **946 MB/s** when the system was idle.
- **The SSD runs hot.** The controller sensor showed 68–69 °C at idle and **75 °C** after a single 1 GB write; the drive's own warning threshold is 70 °C.
- `log show … | sort | uniq -c` showed the system log being flooded:
  - **WindowServer, ~18,700 lines in 5 min:** almost all `[com.apple.Multitouch:Plugin] … dispatchEvent Dispatching event with N children`, one line per trackpad update (VoodooInput presents the trackpad to macOS as an Apple trackpad).
  - **Contacts, AddressBookSourceSync, Family:** ~2,000 lines each.
- `CMFSyncAgent` used up to **77% CPU**, together with `sharingd` (a known Ventura issue with iCloud contacts syncing).
- **iCloud storage was full** (≈49.8 of 50 GB). With iCloud full, uploads can't finish and the sync services keep retrying.
- Photos analysis (`photoanalysisd`, `mediaanalysisd`) and Spotlight (`mds`, `mdbulkimport`) were busy after setting up iCloud.

**Fixes applied**
1. **Stop saving trackpad debug chatter to the SSD.** It's useless noise. The trackpad and its driver logs are unaffected.
   ```bash
   sudo mkdir -p /Library/Preferences/Logging/Subsystems
   sudo defaults write /Library/Preferences/Logging/Subsystems/com.apple.Multitouch DEFAULT-OPTIONS '{ Level = { Enable = Default; Persist = Off; }; }'
   sudo log config --subsystem com.apple.Multitouch --mode "persist:off"     # apply now, without a reboot
   sudo log config --status --subsystem com.apple.Multitouch                 # → DEFAULT PERSIST_OFF
   ```
   - Result: `logd` disk writes roughly halved (68 per 5 s → 61 per 10 s) while using the trackpad.
   - Note that `log show` still counts these lines, because it includes messages held in memory. Check `fs_usage … logd` instead.
   - Undo: `sudo rm /Library/Preferences/Logging/Subsystems/com.apple.Multitouch.plist`
2. **iCloud on the laptop:** turned off **Contacts** ("Keep on My Mac") and **Photos**. Expect a burst of disk work and some lag for 15–30 minutes right after switching them off, while macOS cleans up. Also free up iCloud space (Manage… → remove old device backups) or upgrade the plan.
3. **Fewer background items** (System Settings → General → Login Items → Allow in the Background): turned off Spotify's helper and Microsoft AutoUpdate (Office 16.101 is the last version for Ventura). Google Drive stays on, set to **Stream files**.
4. **Let Spotlight finish its first index**, plugged in and awake: `caffeinate -i -t 7200`.

**Still open:** **SSD cooling.** Check for, or add, a thermal pad between the SSD and the chassis. Under longer writes the controller passes its 70 °C warning level and throttles.

**Useful checks**
```bash
uptime                                                           # load average vs. 2 cores
top -l 2 -n 12 -o cpu -stats command,cpu,mem | tail -13          # who uses the CPU
iostat -d -c 3 -w 1 disk0 | tail -1                              # disk activity
sudo fs_usage -w -f diskio -t 5 2>/dev/null | awk '{print $NF}' | sed 's/\.[0-9]*$//' | sort | uniq -c | sort -rn | head   # who uses the disk
log show --last 5m --style compact 2>/dev/null | awk '{print $4}' | sed 's/\[.*//' | sort | uniq -c | sort -rn | head      # who floods the log
```
SSD health needs smartmontools: Homebrew no longer installs on this Intel/Ventura setup, so use the `.dmg` from smartmontools' SourceForge page, then run `sudo /usr/local/sbin/smartctl -a disk0`.

---

## 4. WhatsApp (Mac App Store) won't reconnect after sleep

**Symptom**
- After waking, WhatsApp stays on "Connecting…".
- Waiting, turning Wi-Fi off and on, or quitting and reopening WhatsApp (⌘Q) doesn't help.
- **A full restart of the laptop fixes it.**

**What was ruled out**
- The network itself: `scutil --nwi` shows Wi-Fi (`en1`) reachable on IPv4 and IPv6, and `curl -4` / `curl -6` to `https://web.whatsapp.com` both return `200`.
- Safari and iMessage work normally after wake.
- `tcpkeepalive` stays **off** on purpose: turning it on brings back background wakes.

**Theory:** something WhatsApp depends on (but Safari and iMessage don't) gets stuck after a wake, and only a reboot clears it. Not confirmed yet. The iCloud and background changes in section 3 may also affect this.

**Next time it happens, before restarting:**

1. Collect information (this only reads):
   ```bash
   pgrep -lf -i whatsapp
   nc -vz -G 5 g.whatsapp.net 443
   nc -vz -G 5 g.whatsapp.net 5222
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

**Workaround:** restart the laptop. WhatsApp Web in Chrome is also unaffected.

---

## 5. Dock magnification doesn't work

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

**Tip:** quit System Settings before changing settings from Terminal, and paste each command on its own line. In this case one line got glued onto a leftover `killall Dock`, so `killall` treated `-bool` as one of its own options and the setting was never saved.
