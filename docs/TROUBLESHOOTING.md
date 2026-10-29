# Troubleshooting: problems found after daily use

These came up after the EFI was finished and published, during normal day-to-day use. Each entry gives the symptom, what the logs showed, the fix, and its current status.

| # | Problem | Status |
|---|---|---|
| 1 | [Trackpad dead after a self-triggered "notification wake"](#1-trackpad-dead-after-a-self-triggered-notification-wake) | ✅ fixed with two settings (still being watched) |
| 2 | [Laptop turns itself back on right after shutdown](#2-laptop-turns-itself-back-on-right-after-shutdown) | ✅ solved (EFI fix) |
| 3 | [Slow first minutes after startup: late login, typing lag, slow apps](#3-slow-first-minutes-after-startup-late-login-typing-lag-slow-apps) | ✅ fixed (boot-time TRIM off + monthly TRIM) |
| 4 | [WhatsApp (Mac App Store) won't reconnect after sleep](#4-whatsapp-mac-app-store-wont-reconnect-after-sleep) | 🔴 under investigation, workaround available |

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

**Result:** it stays off after shutdown, the shutdown cause is `5` (clean).

---

## 3. Slow first minutes after startup: late login, typing lag, slow apps

**Symptom**
- After every startup or restart (not after wake from sleep), the login screen takes much longer than it should.
- At the login screen the cursor spins and typed characters appear seconds later, all at once.
- For several minutes after login, apps take a very long time to open.
- Then everything is normal until the next startup.

**What the logs showed**
- **CPU mostly idle, but a high load average.** Processes were **waiting on the disk**.
- **APFS saves stalling.** The kernel logs `tx_flush: disk1 tx … took N us to flush` for **1 to over 30 seconds** per save, for about 7 minutes after each startup. A normal flush takes milliseconds.
- **The disk is fine otherwise.** SMART was healthy, it was never over its temperature limits, swap was 0, the disk wasn't full, a whole startup wrote only ~200 MB, and it was fast when idle.
- **The trigger is TRIM at mount.** APFS TRIMs **all free space** every time the disk is mounted (`spaceman_scan_free_blocks: … trims took …`). Some NVMe drives acknowledge this immediately but then process it in the background, and stall writes until they're done.
  - The stalls start seconds after that TRIM.
  - With TRIM skipped at boot (`SetApfsTrimTimeout = 0`), the same laptop had **zero** stalled saves and normal app launches.
- The Lenovo/UMIS 256 GB drive listed in the hardware table behaves like this. Other drives may not; [others report the same](https://www.hackintosh-forum.de/forum/thread/56069-monterey-bootet-pl%C3%B6tzlich-sehr-langsam/) on other NVMe models.

**Check whether your drive does it.** Run these about 10 minutes after a startup:
```bash
log show --last boot --style compact --predicate 'eventMessage CONTAINS "to flush"' | grep -E -c 'took [0-9]{7,} us'   # saves that took over 1 s
log show --last boot --style compact --predicate 'eventMessage CONTAINS "spaceman_scan"' | tail -3                      # did TRIM run at boot?
```
Dozens of slow saves right after a TRIM at boot points to this problem. A handful, or none, means your drive is fine: keep the default.

**Fix**
1. **Skip TRIM at boot:** in `config.plist`, set `Kernel → Quirks → SetApfsTrimTimeout` to `0` (default `-1`). Since macOS 12 the only choices are full TRIM at boot (`-1`) or none (`0`). System Information still says "TRIM Support: Yes" with `0`, but that's wrong.
   - **Trade-off:** without TRIM, some SSDs slowly lose write speed over months. It doesn't affect free space or your files.
2. **Give the drive a TRIM once a month, automatically:** the [monthly TRIM scheduler](../scripts/trim-scheduler/) keeps `0` and lets one startup every 30 days run TRIM. It notifies you before that slower restart.
3. **No EFI change:** keep `-1` and mostly use sleep instead of shutting down. TRIM only runs at startup.

**This EFI ships with `-1`** (macOS default), because most drives don't need this.

**Also worth doing (smaller effect)**
1. **Stop saving trackpad debug chatter to the SSD.** With VoodooInput, WindowServer logs `[com.apple.Multitouch:Plugin] … dispatchEvent` for every trackpad update (thousands of lines per minute). The trackpad and its driver logs are unaffected.
   ```bash
   sudo mkdir -p /Library/Preferences/Logging/Subsystems
   sudo defaults write /Library/Preferences/Logging/Subsystems/com.apple.Multitouch DEFAULT-OPTIONS '{ Level = { Enable = Default; Persist = Off; }; }'
   sudo log config --subsystem com.apple.Multitouch --mode "persist:off"     # apply now, without a reboot
   sudo log config --status --subsystem com.apple.Multitouch                 # → DEFAULT PERSIST_OFF
   ```
   - `log show` still counts these lines, because it includes messages held in memory. Check `fs_usage … logd` instead.
   - Undo: `sudo rm /Library/Preferences/Logging/Subsystems/com.apple.Multitouch.plist`
2. **Keep login light:** in System Settings → General → Login Items (both lists), switch off background items you don't need at startup.
3. **Let Spotlight finish its first index** after setup, plugged in and awake: `caffeinate -i -t 7200`.

**Useful checks**
```bash
uptime                                                           # load average vs. 2 cores
top -l 2 -n 12 -o cpu -stats command,cpu,mem | tail -13          # who uses the CPU
iostat -d -c 3 -w 1 disk0 | tail -1                              # disk activity
sudo fs_usage -w -f diskio -t 5 2>/dev/null | awk '{print $NF}' | sed 's/\.[0-9]*$//' | sort | uniq -c | sort -rn | head   # who uses the disk
log show --last 5m --style compact 2>/dev/null | awk '{print $4}' | sed 's/\[.*//' | sort | uniq -c | sort -rn | head      # who floods the log
```

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

**Theory:** something WhatsApp depends on (but Safari and iMessage don't) gets stuck after a wake, and only a reboot clears it. Not confirmed yet. 

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
