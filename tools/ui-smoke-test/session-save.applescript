on elementWithIdentifier(theProcess, identifierValue)
    tell application "System Events"
        try
            set candidates to entire contents of window 1 of theProcess
        on error
            return missing value
        end try
    end tell
    repeat with candidate in candidates
        try
            tell application "System Events" to set candidateID to value of attribute "AXIdentifier" of candidate
            if candidateID is identifierValue then return candidate
        end try
    end repeat
    return missing value
end elementWithIdentifier

on waitForIdentifier(theProcess, identifierValue, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set candidate to my elementWithIdentifier(theProcess, identifierValue)
        if candidate is not missing value then return candidate
        delay 0.2
    end repeat
    error "Timed out waiting for accessibility identifier " & identifierValue
end waitForIdentifier

on clickIdentifier(theProcess, identifierValue)
    set candidate to my waitForIdentifier(theProcess, identifierValue, 20)
    tell application "System Events"
        try
            perform action "AXPress" of candidate
        on error
            click candidate
        end try
    end tell
end clickIdentifier

on run argv
    if (count of argv) is not 2 then error "Expected app PID and save directory"
    set appPID to item 1 of argv as integer
    set saveDirectory to item 2 of argv
    tell application "System Events"
        set appProcess to first application process whose unix id is appPID
        set frontmost of appProcess to true
    end tell

    my waitForIdentifier(appProcess, "dataset.card", 30)
    my waitForIdentifier(appProcess, "result.viewer", 30)
    my clickIdentifier(appProcess, "workspace.results")
    delay 1
    my clickIdentifier(appProcess, "result.saveSession")
    delay 1.5
    tell application "System Events"
        keystroke "g" using {command down, shift down}
        delay 1
        keystroke saveDirectory
        key code 36
        delay 2
        key code 36
    end tell
    delay 5
    return "PASS: first Save to Session published a new sidecar"
end run
