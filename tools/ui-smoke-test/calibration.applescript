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
    if (count of argv) is not 1 then error "Expected app PID"
    set appPID to item 1 of argv as integer
    tell application "System Events"
        set appProcess to first application process whose unix id is appPID
        set frontmost of appProcess to true
    end tell

    my waitForIdentifier(appProcess, "dataset.card", 30)
    my waitForIdentifier(appProcess, "calibration.readiness", 10)
    set started to current date
    set actionButton to my waitForIdentifier(appProcess, "calibration.action.originProbe", 10)
    tell application "System Events" to click actionButton

    set deadline to (current date) + 30
    repeat while (current date) < deadline
        if my elementWithIdentifier(appProcess, "calibration.action.originProbe") is missing value then exit repeat
        delay 0.2
    end repeat
    if my elementWithIdentifier(appProcess, "calibration.action.originProbe") is not missing value then error "Origin calibration did not publish"
    return "PASS: fresh demo -> visible readiness -> origin calibration (" & ((current date) - started) & " s)"
end run
