#!/bin/bash
# Monthly SSD TRIM for OpenCore. Keeps SetApfsTrimTimeout at 0 (TRIM skipped at boot)
# and lets one boot run TRIM (-1) every DAYS days.
DAYS=30
STATE_DIR="/Library/Application Support/TrimScheduler"
STAMP="$STATE_DIR/last-trim"
LOG="$STATE_DIR/trim-scheduler.log"
PB=/usr/libexec/PlistBuddy
KEY=":Kernel:Quirks:SetApfsTrimTimeout"

mkdir -p "$STATE_DIR"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
notify() {
  for i in $(seq 1 60); do
    U=$(stat -f %Su /dev/console)
    if [ -n "$U" ] && [ "$U" != "root" ]; then
      launchctl asuser "$(id -u "$U")" sudo -u "$U" osascript -e "display notification \"$1\" with title \"SSD TRIM\"" >/dev/null 2>&1
      return
    fi
    sleep 15
  done
}

sleep "${TRIM_SCHED_DELAY:-120}"

PS=$(diskutil info / | awk -F': *' '/APFS Physical Store/{print $2; exit}')
WHOLE=$(echo "$PS" | sed -E 's/s[0-9]+$//')
EFI="${WHOLE}s1"
if [ -z "$PS" ] || ! diskutil info "$EFI" | grep -q "Partition Type:.*EFI"; then
  log "EFI partition not found ($EFI), nothing changed"; exit 0
fi

mpoint() { diskutil info "$EFI" | awk -F': *' '/Mount Point/{print $2; exit}'; }
MP=$(mpoint); WEMOUNTED=0
if [ -z "$MP" ]; then
  diskutil mount "$EFI" >/dev/null 2>&1 || { log "could not mount $EFI"; exit 0; }
  WEMOUNTED=1; MP=$(mpoint)
fi
CFG="$MP/EFI/OC/config.plist"
finish() { [ "$WEMOUNTED" = 1 ] && diskutil unmount "$EFI" >/dev/null 2>&1; }

if [ ! -f "$CFG" ]; then log "no config at $CFG"; finish; exit 0; fi
CUR=$($PB -c "Print $KEY" "$CFG" 2>/dev/null)
if [ -z "$CUR" ]; then log "SetApfsTrimTimeout not found in config"; finish; exit 0; fi

setval() {
  TMP="$MP/EFI/OC/config.plist.trimtmp"
  cp "$CFG" "$STATE_DIR/config-before-$(date +%Y%m%d-%H%M).plist"
  if cp "$CFG" "$TMP" && $PB -c "Set $KEY $1" "$TMP" && plutil -lint -s "$TMP" && mv "$TMP" "$CFG"; then
    log "set SetApfsTrimTimeout=$1 ($2)"; return 0
  fi
  rm -f "$TMP"; log "FAILED to set $1, config left unchanged"; return 1
}

NOW=$(date +%s)
LAST=$(cat "$STAMP" 2>/dev/null); LAST=${LAST:-0}
AGE=$(( (NOW - LAST) / 86400 ))

if [ "$CUR" = "-1" ]; then
  echo "$NOW" > "$STAMP"
  setval 0 "this boot ran TRIM; next boots skip it" && N="This startup ran the monthly TRIM. The next startups are fast again."
elif [ "$CUR" = "0" ] && [ "$AGE" -ge "$DAYS" ]; then
  setval -1 "last TRIM $AGE days ago; next boot runs TRIM" && N="Your next restart runs the monthly TRIM and will be slow for a few minutes."
else
  log "no change (value $CUR, last TRIM $AGE days ago)"
fi
finish
[ -n "$N" ] && notify "$N"
exit 0
