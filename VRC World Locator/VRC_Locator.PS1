# VRChat World Logger with Enhanced Execution Policy Check
# This script continuously monitors the VRChat log file to extract the current world name and instance type.
# It first checks if the execution policy is set to 'RemoteSigned' to prevent errors.

# Check if the current session is running as Administrator.
# ---------------------------------------------------------------------

# --- Execution Policy Check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
$currentPolicy = Get-ExecutionPolicy -Scope LocalMachine
Write-Host "Current Execution Policy for LocalMachine is: $currentPolicy"

if ($currentPolicy -ne 'RemoteSigned') {
    if ($isAdmin) {
        $choice = Read-Host "Execution policy 'RemoteSigned' is required. Set now? (Y/N)"
        if ($choice -match '^[Yy]$') {
            Write-Host "Setting Execution Policy to 'RemoteSigned'..." -ForegroundColor Cyan
            Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force | Out-Null
            Write-Host "Execution Policy set successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Execution Policy was not changed. Exiting..." -ForegroundColor Yellow
            Read-Host "Press Enter to exit..."
            exit
        }
    }
    else {
        Write-Host "Run PowerShell as Administrator to set execution policy." -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
        exit
    }
}

Write-Host "Execution Policy OK. Starting real-time logger..." -ForegroundColor Green

# --- Setup Variables ---
$logDirectory = "$env:USERPROFILE\AppData\LocalLow\VRChat\VRChat"
$worldOutputFile  = "VRChat_Current_World.txt"
$checkIntervalSeconds = 2 # New, faster check interval

# --- VRChat Log Monitoring Loop ---
while ($true) {

    # Find the latest log file on every iteration in case VRChat restarts
    $latestLogFile = Get-ChildItem -Path $logDirectory -Filter "output_log_*.txt" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestLogFile) {

        # --- SMART LINE TAILING (INCREASED BUFFER FOR BETTER HISTORY) ---
        $fileSizeMB = [math]::Round((Get-Item $latestLogFile.FullName).Length / 1MB, 1)

        switch ($fileSizeMB) {
            # Increased these counts significantly to cover more history, at the cost of slight speed reduction
            { $_ -gt 800 } { $tailCount = 15000; break }
            { $_ -gt 600 } { $tailCount = 20000; break }
            { $_ -gt 400 } { $tailCount = 30000; break }
            { $_ -gt 250 } { $tailCount = 40000; break }
            { $_ -gt 150 } { $tailCount = 50000; break }
            { $_ -gt 80  } { $tailCount = 75000; break }
            { $_ -gt 50  } { $tailCount = 100000; break }
            default        { $tailCount = 150000 }
        }

        # Added back debug message to show line count and log size
        Write-Host "Reading last $tailCount lines (log size: $fileSizeMB MB)" -ForegroundColor DarkGray

        $logContent = Get-Content -Path $latestLogFile.FullName -Tail $tailCount -ErrorAction SilentlyContinue

        # --- MULTI-PATTERN SEARCH (more reliable) ---
        $roomEntry = $logContent | Select-String -Pattern "Joining or Creating Room:" | Select-Object -Last 1
        $destinationEntry = $logContent | Select-String -Pattern "Destination fetching:" | Select-Object -Last 1

        # If "Entering Room:" is used instead (some builds)
        if (-not $roomEntry) {
            $roomEntry = $logContent | Select-String -Pattern "Entering Room:" | Select-Object -Last 1
        }

        if ($roomEntry -and $destinationEntry) {

            # --- Extract World Name ---
            $worldName = "Unknown World"

            if ($roomEntry.ToString() -match 'Room:\s(.+)$') {
                $worldName = $matches[1].Trim()
            }

            # --- Parse Instance String ---
            $destinationInfo = $destinationEntry.ToString()

            $instanceType = "Public"
            $groupId = ""
            $ageGate = ""

            if ($destinationInfo -match 'group\((grp_[a-zA-Z0-9-]+)\)') {
                $groupId = $matches[1]

                if ($destinationInfo -match 'groupAccessType\(public\)')   { $instanceType = "Group Public" }
                elseif ($destinationInfo -match 'groupAccessType\(plus\)') { $instanceType = "Group Plus" }
                elseif ($destinationInfo -match 'groupAccessType\(members\)') { $instanceType = "Group Members" }
                else { $instanceType = "Group" }
            }
            elseif ($destinationInfo -match 'friends\+') { $instanceType = "Friends+" }
            elseif ($destinationInfo -match '~hidden')   { $instanceType = "Friends+" }
            elseif ($destinationInfo -match 'friends')   { $instanceType = "Friends" }
            elseif ($destinationInfo -match 'invite\+')  { $instanceType = "Invite+" }
            elseif ($destinationInfo -match 'private')   { $instanceType = "Invite" }

            if ($destinationInfo -match '~ageGate') { $ageGate = " 18+" }

            # --- Format output ---
            $outputString = "$worldName`n($instanceType$ageGate"
            if ($groupId) { $outputString += ", $groupId)" } else { $outputString += ")" }

            # --- Write only if changed ---
            $existing = Get-Content -Path $worldOutputFile -ErrorAction SilentlyContinue

            if ($existing -ne $outputString) {
                Set-Content -Path $worldOutputFile -Value $outputString -Force
                Write-Host "--- World Updated ($fileSizeMB MB Log Size) ---" -ForegroundColor Yellow
                Write-Host $outputString -ForegroundColor Cyan
                Write-Host "---------------------------------------------------" -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host "VRChat log file not found. Is VRChat running?" -ForegroundColor Red
    }

    # --- Pause for real-time responsiveness ---
    Start-Sleep -Seconds $checkIntervalSeconds
}
