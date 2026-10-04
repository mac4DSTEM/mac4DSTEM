#!/bin/zsh
# usage: drive.sh <probe-binary> <scenario> <outdir>
#   scenarios: crash-last | crash-first | remount | remount-nocheck
# Creates ONE RAM disk (and, for remount scenarios, a second one) named mac4dstemD; detaches every one it made.
PROBE=$1; SCEN=$2; OUT=$3; mkdir -p $OUT
VOL=mac4dstemD; MNT=/Volumes/$VOL; FILE=$MNT/cube.dm4
LOG=$OUT/$SCEN.log; : > $LOG
CTL=$OUT/$SCEN.ctl; rm -f $CTL; mkfifo $CTL
DEVS=()
note() { echo "$@" | tee -a $LOG; }
mkram() {
  local dev; dev=$(hdiutil attach -nomount ram://131072 | awk '{print $1}')
  DEVS+=($dev)
  diskutil erasevolume HFS+ $VOL $dev > /dev/null 2>&1
  note "ram disk $dev mounted at $(diskutil info $dev | awk -F': *' '/Mount Point/{print $2}')"
}
cleanup() { for d in $DEVS; do hdiutil detach -force $d > /dev/null 2>&1; done; rm -f $CTL }
trap cleanup EXIT; trap "" PIPE
waitfor() { # waitfor <pattern> <seconds>
  local i=0; while (( i < $2*10 )); do grep -q -- "$1" $PROBE_LOG 2>/dev/null && return 0; kill -0 $PID 2>/dev/null || return 1; sleep 0.1; i=$((i+1)); done; return 1
}
mkram
$PROBE write $FILE >> $LOG 2>&1
PROBE_LOG=$OUT/$SCEN.probe.log; : > $PROBE_LOG
$PROBE run $FILE < $CTL > $PROBE_LOG 2>&1 &
PID=$!
exec 3> $CTL
waitfor READY 30 || { note "probe never reached READY"; cat $PROBE_LOG >> $LOG; exit 1; }
note "--- probe READY; yanking: hdiutil detach -force ${DEVS[1]}"
hdiutil detach -force ${DEVS[1]} >> $LOG 2>&1; note "detach exit=$?"
case $SCEN in
  crash-last)  echo "check after-yank" >&3; sleep 1; echo "read last" >&3 ;;
  crash-first) echo "check after-yank" >&3; sleep 1; echo "read first" >&3 ;;
  guard-yank)  echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
  guard-remount)
    echo "read first" >&3; sleep 1
    mkram; $PROBE write $FILE >> $LOG 2>&1
    note "--- same volume name and path back: $(ls -l $FILE 2>&1)"
    echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
  guard-remount-nocheck)
    mkram; $PROBE write $FILE >> $LOG 2>&1
    note "--- same volume name and path back, NO read ran while the disk was gone: $(ls -l $FILE 2>&1)"
    echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
  remount|remount-nocheck)
    [[ $SCEN == remount ]] && { echo "check after-yank" >&3; sleep 1; }
    mkram
    $PROBE write $FILE >> $LOG 2>&1
    note "--- same volume name and path back: $(ls -l $FILE 2>&1)"
    echo "check after-remount" >&3; sleep 1
    echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
esac
sleep 3
exec 3>&-
wait $PID; STATUS=$?
note "--- probe exit status: $STATUS  (138 = SIGBUS, 139 = SIGSEGV, 0 = clean)"
cat $PROBE_LOG >> $LOG
