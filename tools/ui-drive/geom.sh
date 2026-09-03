#!/bin/zsh
# The running app's column split, one line per child: class x width
# (accessibility, no screenshot needed). Read it before and after a drag.
osascript -e 'tell application "System Events" to tell process "mac4DSTEM"
  set sg to splitter group 1 of group 1 of window 1
  set out to ""
  repeat with e in (every UI element of sg)
    set p to position of e
    set z to size of e
    set out to out & (class of e as string) & " " & (item 1 of p as string) & " " & (item 1 of z as string) & linefeed
  end repeat
  return out
end tell'
