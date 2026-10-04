#!/bin/zsh
# usage: refdrive.sh <probe> <FS: HFS+|ExFAT|APFS> <scenario: yank|eject|unmount-remount> <outdir> <tag>
# Creates ONE RAM disk named mac4dstemDref (never any other volume) and detaches it on exit.
PROBE=$1; FS=$2; SCEN=$3; OUT=$4; TAG=$5; mkdir -p $OUT
VOL=${VOLNAME:-mac4dstemDref}; MNT=/Volumes/$VOL; FILE=$MNT/cube.dm4
LOG=$OUT/$TAG.log; : > $LOG
CTL=$OUT/$TAG.ctl; rm -f $CTL; mkfifo $CTL
DEVS=()
note() { echo "$@" | tee -a $LOG; }
mkram() {
  local dev; dev=$(hdiutil attach -nomount ram://131072 | awk '{print $1}')
  DEVS+=($dev)
  diskutil erasevolume "$FS" $VOL $dev >> $LOG 2>&1
  VOLDEV=$(diskutil info $MNT | awk -F': *' '/Device Node/{print $2}')
  note "ram disk $dev ($FS) volume device $VOLDEV mounted at $(diskutil info $MNT | awk -F': *' '/Mount Point/{print $2}') mount line: $(mount | grep " on $MNT ")"
}
cleanup() { for d in $DEVS; do hdiutil detach -force $d > /dev/null 2>&1; done; rm -f $CTL }
trap cleanup EXIT; trap "" PIPE
waitfor() { local i=0; while (( i < $2*10 )); do grep -q -- "$1" $PROBE_LOG 2>/dev/null && return 0; kill -0 $PID 2>/dev/null || return 1; sleep 0.1; i=$((i+1)); done; return 1 }
mkram
$PROBE write $FILE >> $LOG 2>&1
PROBE_LOG=$OUT/$TAG.probe.log; : > $PROBE_LOG
$PROBE run $FILE < $CTL > $PROBE_LOG 2>&1 &
PID=$!
exec 3> $CTL
waitfor READY 30 || { note "probe never reached READY"; cat $PROBE_LOG >> $LOG; exit 1; }
case $SCEN in
  yank)
    note "--- yank: hdiutil detach -force ${DEVS[1]}"; hdiutil detach -force ${DEVS[1]} >> $LOG 2>&1; note "detach exit=$?"
    echo "check after-yank" >&3; sleep 1; echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
  eject)
    note "--- eject: diskutil eject force ${DEVS[1]}"; diskutil eject force ${DEVS[1]} >> $LOG 2>&1; note "eject exit=$?"
    echo "check after-eject" >&3; sleep 1; echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
  unmount-remount)
    note "--- soft: diskutil unmount $MNT (expected to be refused: file mapped/open)"; diskutil unmount $MNT >> $LOG 2>&1; note "soft unmount exit=$?"
    note "--- diskutil unmount force $MNT"; diskutil unmount force $MNT >> $LOG 2>&1; note "force unmount exit=$?"
    echo "check after-unmount" >&3; sleep 1; echo "read first" >&3; sleep 1
    note "--- diskutil mount $VOLDEV (same device, same file, same inode)"; diskutil mount $VOLDEV >> $LOG 2>&1; note "mount exit=$? : $(ls -li $FILE 2>&1)"
    echo "check after-remount" >&3; sleep 1; echo "read first" >&3; sleep 1; echo "read last" >&3 ;;
esac
sleep 3
exec 3>&-
wait $PID; STATUS=$?
note "--- probe exit status: $STATUS  (138 = SIGBUS, 139 = SIGSEGV, 0 = clean)"
cat $PROBE_LOG >> $LOG
