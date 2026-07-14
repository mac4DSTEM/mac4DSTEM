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

on run argv
    if (count of argv) is not 2 then error "Expected app PID and dataset path"
    set appPID to item 1 of argv as integer
    set datasetPath to item 2 of argv

    tell application "System Events"
        set appProcess to first application process whose unix id is appPID
        set frontmost of appProcess to true
    end tell

    if datasetPath is "--check" then
        my waitForIdentifier(appProcess, "dataset.card", 10)
        return "PASS: a real dataset is loaded"
    end if

    tell application "System Events"
        keystroke "o" using command down
        delay 1.5
        keystroke "g" using {command down, shift down}
        delay 1
        keystroke datasetPath
        key code 36
        delay 2
        key code 36
    end tell

    my waitForIdentifier(appProcess, "dataset.card", 45)
    return "PASS: imported " & datasetPath
end run
