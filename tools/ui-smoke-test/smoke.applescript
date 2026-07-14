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
        set frontmost of theProcess to true
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

on waitForResultContaining(theProcess, expectedText, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set resultTitle to my waitForIdentifier(theProcess, "result.title", 5)
        set resultName to my accessibleText(resultTitle)
        if resultName contains expectedText then return resultName
        delay 0.2
    end repeat
    set statusText to "unavailable"
    set statusElement to my elementWithIdentifier(theProcess, "status.bar")
    if statusElement is not missing value then set statusText to my accessibleText(statusElement)
    error "Timed out waiting for result containing " & expectedText & "; status: " & statusText
end waitForResultContaining

on run argv
    if (count of argv) is not 1 then error "Expected app PID"
    set appPID to item 1 of argv as integer
    tell application "System Events"
        set appProcess to first application process whose unix id is appPID
        set frontmost of appProcess to true
    end tell

    my waitForIdentifier(appProcess, "dataset.card", 30)
    my waitForIdentifier(appProcess, "calibration.readiness", 10)

    set imageStarted to current date
    my clickIdentifier(appProcess, "workspace.image")
    my clickIdentifier(appProcess, "task.Virtual Det")
    try
        my clickIdentifier(appProcess, "workspace.primaryAction")
    on error messageText
        error "Image primary action: " & messageText
    end try
    my waitForResultContaining(appProcess, "Virtual detector", 30)
    set imageSeconds to (current date) - imageStarted

    set dpcStarted to current date
    my clickIdentifier(appProcess, "task.DPC")
    try
        my clickIdentifier(appProcess, "workspace.primaryAction")
    on error messageText
        error "DPC primary action: " & messageText
    end try
    my waitForResultContaining(appProcess, "DPC", 30)
    set dpcSeconds to (current date) - dpcStarted

    my clickIdentifier(appProcess, "workspace.map")
    my clickIdentifier(appProcess, "task.Disks")
    set braggStarted to current date
    try
        my clickIdentifier(appProcess, "workspace.primaryAction")
    on error messageText
        error "Bragg primary action: " & messageText
    end try
    my waitForResultContaining(appProcess, "Bragg vector map", 30)
    set braggSeconds to (current date) - braggStarted

    set strainStarted to current date
    my clickIdentifier(appProcess, "task.Strain")
    try
        my clickIdentifier(appProcess, "workspace.primaryAction")
    on error messageText
        error "Strain primary action: " & messageText
    end try
    my waitForResultContaining(appProcess, "Strain", 30)
    set strainSeconds to (current date) - strainStarted

    my clickIdentifier(appProcess, "task.ACOM")
    my waitForIdentifier(appProcess, "acom.scope", 10)
    set acomStarted to current date
    try
        my clickIdentifier(appProcess, "workspace.primaryAction")
    on error messageText
        error "ACOM primary action: " & messageText
    end try
    my waitForResultContaining(appProcess, "ACOM preview", 30)
    set acomSeconds to (current date) - acomStarted

    set reconstructionStarted to current date
    my clickIdentifier(appProcess, "workspace.reconstruct")
    try
        my clickIdentifier(appProcess, "workspace.primaryAction")
    on error messageText
        error "Reconstruction primary action: " & messageText
    end try
    my waitForResultContaining(appProcess, "Parallax incoherent BF preview", 30)
    my waitForIdentifier(appProcess, "result.scanNavigator", 10)
    set reconstructionSeconds to (current date) - reconstructionStarted

    my clickIdentifier(appProcess, "workspace.results")
    my waitForIdentifier(appProcess, "result.viewer", 10)
    my waitForIdentifier(appProcess, "result.exportPNG", 10)
    my waitForIdentifier(appProcess, "result.exportBundle", 10)
    return "PASS: image=" & imageSeconds & "s dpc=" & dpcSeconds & "s bragg=" & braggSeconds & "s strain=" & strainSeconds & "s acom=" & acomSeconds & "s reconstruct=" & reconstructionSeconds & "s -> Results"
end run
