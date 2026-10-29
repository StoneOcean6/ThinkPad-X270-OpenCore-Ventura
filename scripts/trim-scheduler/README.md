# Monthly TRIM scheduler

For drives that stall for minutes after the boot-time TRIM (see [Troubleshooting §3](../../docs/TROUBLESHOOTING.md#3-slow-first-minutes-after-startup-late-login-typing-lag-slow-apps)). With `SetApfsTrimTimeout = 0` the drive never gets TRIM. This keeps it at `0` for fast startups and lets **one startup every 30 days** run TRIM.

**How it works** (a LaunchDaemon that runs once, 2 minutes after each startup):
- `SetApfsTrimTimeout` is `0` and the last TRIM was over 30 days ago → it sets `-1`, so the **next** startup runs TRIM. A notification warns that restart will be slow for a few minutes.
- `SetApfsTrimTimeout` is `-1` (that TRIM startup) → it records the date and sets `0` again. A notification confirms it.
- Otherwise it changes nothing.

**Safety:**
- Before each change it saves a copy of `config.plist` to `/Library/Application Support/TrimScheduler/`.
- It edits a temporary copy, checks it with `plutil -lint`, and only then replaces the real config.
- It mounts the EFI partition only if it isn't mounted already, and unmounts it again afterwards.
- It finds the EFI partition from the boot disk (`diskutil info /`), not from a fixed disk number.

## Install

Set `Kernel → Quirks → SetApfsTrimTimeout` to `0` in your `config.plist` first. Then, from this folder, run `sudo -v` on its own, followed by:
```bash
sudo mkdir -p /usr/local/sbin "/Library/Application Support/TrimScheduler"
sudo cp trim-scheduler.sh /usr/local/sbin/
sudo cp local.trim-scheduler.plist /Library/LaunchDaemons/
sudo chown root:wheel /usr/local/sbin/trim-scheduler.sh /Library/LaunchDaemons/local.trim-scheduler.plist
sudo chmod 755 /usr/local/sbin/trim-scheduler.sh
sudo chmod 644 /Library/LaunchDaemons/local.trim-scheduler.plist
date +%s | sudo tee "/Library/Application Support/TrimScheduler/last-trim" >/dev/null
sudo launchctl bootstrap system /Library/LaunchDaemons/local.trim-scheduler.plist
```
The `date` line counts today as the last TRIM. Leave it out if you want a TRIM startup soon.

- It shows in **System Settings → General → Login Items → Allow in the Background** as **bash**. Keep it on.
- Notifications appear under **Script Editor**. Allow them in **System Settings → Notifications**.
- Test a notification:
  ```bash
  sudo launchctl asuser $(id -u) sudo -u $USER osascript -e 'display notification "Test" with title "SSD TRIM"'
  ```

## Check / remove

```bash
cat "/Library/Application Support/TrimScheduler/trim-scheduler.log"
```
```bash
sudo launchctl bootout system/local.trim-scheduler
sudo rm /Library/LaunchDaemons/local.trim-scheduler.plist /usr/local/sbin/trim-scheduler.sh
```
Change `DAYS=30` at the top of the script for a different interval.
