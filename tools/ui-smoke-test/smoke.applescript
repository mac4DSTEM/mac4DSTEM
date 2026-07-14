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

on accessibleText(candidate)
    repeat with attributeName in {"AXTitle", "AXValue", "AXDescription"}
        try
            tell application "System Events" to set textValue to value of attribute attributeName of candidate
            if textValue is not missing value and textValue is not "" then return textValue as text
        end try
    end repeat
    return ""
end accessibleText

on run argv
    if (count of argv) is not 1 then error "Expected app PID"
    set appPID to item 1 of argv as integer
    tell application "System Events"
        set appProcess to first application process whose unix id is appPID
        set frontmost of appProcess to true
    end tell

    my waitForIdentifier(appProcess, "dataset.card", 30)
    my clickIdentifier(appProcess, "workspace.map")
    my clickIdentifier(appProcess, "task.Disks")
    set diskAction to my waitForIdentifier(appProcess, "workspace.primaryAction", 10)
    tell application "System Events" to click diskAction

    delay 0.5
    my waitForIdentifier(appProcess, "workspace.primaryAction", 30)

    my clickIdentifier(appProcess, "task.ACOM")
    my waitForIdentifier(appProcess, "acom.scope", 10)
    set previewAction to my waitForIdentifier(appProcess, "workspace.primaryAction", 10)
    tell application "System Events" to click previewAction

    delay 0.5
    set resultTitle to my waitForIdentifier(appProcess, "result.title", 30)
    set deadline to (current date) + 30
    repeat while (current date) < deadline
        set resultName to my accessibleText(resultTitle)
        if resultName contains "ACOM preview" then exit repeat
        delay 0.2
        set resultTitle to my waitForIdentifier(appProcess, "result.title", 5)
    end repeat
    set resultName to my accessibleText(resultTitle)
    if resultName does not contain "ACOM preview" then error "Preview result was not published: " & resultName

    my clickIdentifier(appProcess, "workspace.results")
    my waitForIdentifier(appProcess, "result.viewer", 10)
    return "PASS: demo → Map → Bragg disks → ACOM preview → Results"
end run
