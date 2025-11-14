# VRChat World Logger with Enhanced Execution Policy Check
# This script continuously monitors the VRChat log file to extract the current world name and instance type.
# It first checks if the execution policy is set to 'RemoteSigned' to prevent errors.

# Check if the current session is running as Administrator.
# --- Execution Policy Check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
$currentPolicy = Get-ExecutionPolicy -Scope LocalMachine
Write-Host "Current Execution Policy for LocalMachine is: $currentPolicy"

if ($currentPolicy -ne 'RemoteSigned') {
    if ($isAdmin) {
        $choice = Read-Host "Execution policy 'RemoteSigned' is required. Would you like to set it now? (Y/N)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Setting Execution Policy to 'RemoteSigned'..." -ForegroundColor Cyan
            Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force | Out-Null
            Write-Host "Execution Policy set successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Execution Policy was not changed. The script cannot proceed." -ForegroundColor Yellow
            Read-Host "Press Enter to exit..."
            exit
        }
    }
    else {
        Write-Host "Execution policy 'RemoteSigned' is required to run this script." -ForegroundColor Yellow
        Write-Host "Please open PowerShell as an Administrator and run this script again to set the policy." -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
        exit
    }
}

Write-Host "Execution Policy check passed. Starting the VRChat World Logger..." -ForegroundColor Green

# --- VRChat Log Monitoring and System Performance Loop ---
while ($true) {
    # --- VRChat World Info ---
    $logDirectory = "$env:USERPROFILE\AppData\LocalLow\VRChat\VRChat"
    $outputFile = "VRChat_Current_World.txt"
    $latestLogFile = Get-ChildItem -Path $logDirectory -Filter "output_log_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($null -ne $latestLogFile) {
        # Dynamically choose how many lines to read based on log size
        $fileSizeMB = [math]::Round((Get-Item $latestLogFile.FullName).Length / 1MB, 2)

        if ($fileSizeMB -gt 500) {
            $tailCount = 3000
        }
        elseif ($fileSizeMB -gt 300) {
            $tailCount = 4000
        }
        elseif ($fileSizeMB -gt 200) {
            $tailCount = 6000
        }
        elseif ($fileSizeMB -gt 120) {
            $tailCount = 8000
        }
        elseif ($fileSizeMB -gt 100) {
            $tailCount = 9000
        }
        elseif ($fileSizeMB -gt 50) {
            $tailCount = 12000
        }
        elseif ($fileSizeMB -gt 10) {
            $tailCount = 20000
        }
        else {
            $tailCount = 30000
        }

        Write-Host "Reading last $tailCount lines (log size: $fileSizeMB MB)" -ForegroundColor Yellow

        $logContent = Get-Content -Path $latestLogFile.FullName -Tail $tailCount
        $roomEntry = $logContent | Select-String -Pattern "\[Behaviour\] Joining or Creating Room: " | Select-Object -Last 1
        $destinationEntry = $logContent | Select-String -Pattern "\[Behaviour\] Destination fetching: " | Select-Object -Last 1

        if ($null -ne $destinationEntry -and $null -ne $roomEntry) {
            $worldName = "Unknown World"
            if ($roomEntry.ToString() -match '\[Behaviour\] Joining or Creating Room: (.*)') {
                $worldName = $matches[1].Trim()
            }

            $destinationInfo = $destinationEntry.ToString()
            $instanceType = "Public"
            $groupId = ""
            $ageGate = ""

            if ($destinationInfo -match 'group\((grp_[a-zA-Z0-9-]+)\)') {
                $groupId = $matches[1]
                if ($destinationInfo -match 'groupAccessType\(public\)') { $instanceType = "Group Public" }
                elseif ($destinationInfo -match 'groupAccessType\(plus\)') { $instanceType = "Group Plus" }
                elseif ($destinationInfo -match 'groupAccessType\(members\)') { $instanceType = "Group Members" }
                else { $instanceType = "Group" }
            }
            elseif ($destinationInfo -match 'friends\+') { $instanceType = "Friends+" }
            elseif ($destinationInfo -match '~hidden') { $instanceType = "Friends+" }
            elseif ($destinationInfo -match 'friends') { $instanceType = "Friends" }
            elseif ($destinationInfo -match 'invite\+') { $instanceType = "Invite+" }
            elseif ($destinationInfo -match '~canRequestInvite') { $instanceType = "Invite+" }
            elseif ($destinationInfo -match 'private') { $instanceType = "Invite" }

            if ($destinationInfo -match '~ageGate') { $ageGate = " 18+" }

            $outputString = "$worldName`n($instanceType$ageGate"
            if ($groupId) { $outputString += ", $groupId)" } else { $outputString += ")" }

            $currentOutputInFile = Get-Content -Path $outputFile -ErrorAction SilentlyContinue
            if ($currentOutputInFile -ne $outputString) {
                Set-Content -Path $outputFile -Value $outputString -Force
                Write-Host "New world information found and saved to '$outputFile'." -ForegroundColor Cyan
                Write-Host $outputString
            }
        }
    }
    else {
        Write-Output "No VRChat log files found at '$logDirectory'. Waiting 15 seconds..."
    }

    # Wait before next check
    Start-Sleep -Seconds 15
}
