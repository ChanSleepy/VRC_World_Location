# VRChat World Logger with System Performance Monitor (Real-Time Update)
# ---------------------------------------------------------------------

# --- Execution Policy Check---
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
$worldOutputFile = "VRChat_Current_World.txt"
$perfLogFile = "System_Performance_Log.txt"
$perfCounter = 0
$checkIntervalSeconds = 2

# --- VRChat Log Monitoring Loop ---
while ($true) {

    # Find the latest log file on every iteration in case VRChat restarts
    $latestLogFile = Get-ChildItem -Path $logDirectory -Filter "output_log_*.txt" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestLogFile) {

        # --- SMART LINE TAILING ---
        $fileSizeMB = [math]::Round((Get-Item $latestLogFile.FullName).Length / 1MB, 1)

        switch ($fileSizeMB) {
            { $_ -gt 800 } { $tailCount = 15000; break }
            { $_ -gt 600 } { $tailCount = 20000; break }
            { $_ -gt 400 } { $tailCount = 30000; break }
            { $_ -gt 250 } { $tailCount = 40000; break }
            { $_ -gt 150 } { $tailCount = 50000; break }
            { $_ -gt 80 } { $tailCount = 75000; break }
            { $_ -gt 50 } { $tailCount = 100000; break }
            default { $tailCount = 150000 }
        }

        Write-Host "Reading last $tailCount lines (log size: $fileSizeMB MB)" -ForegroundColor DarkGray

        $logContent = Get-Content -Path $latestLogFile.FullName -Tail $tailCount -ErrorAction SilentlyContinue

        # --- MULTI-PATTERN SEARCH ---
        $roomEntry = $logContent | Select-String -Pattern "Joining or Creating Room:" | Select-Object -Last 1
        $destinationEntry = $logContent | Select-String -Pattern "Destination fetching:" | Select-Object -Last 1

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

                if ($destinationInfo -match 'groupAccessType\(public\)') { $instanceType = "Group Public" }
                elseif ($destinationInfo -match 'groupAccessType\(plus\)') { $instanceType = "Group Plus" }
                elseif ($destinationInfo -match 'groupAccessType\(members\)') { $instanceType = "Group Members" }
                else { $instanceType = "Group" }
            }
            elseif ($destinationInfo -match 'friends\+') { $instanceType = "Friends+" }
            elseif ($destinationInfo -match '~hidden') { $instanceType = "Friends+" }
            elseif ($destinationInfo -match 'friends') { $instanceType = "Friends" }
            elseif ($destinationInfo -match 'invite\+') { $instanceType = "Invite+" }
            elseif ($destinationInfo -match 'private') { $instanceType = "Invite" }

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

    # --- System Performance Logging (every 1 cycle) ---
    if ($perfCounter -ge 1) {

        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        $totalMem = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB
        $freeMem = (Get-Counter '\Memory\Available MBytes').CounterSamples.CookedValue
        $usedMem = [math]::Round($totalMem - $freeMem, 1)
        $cpuPercent = [math]::Round($cpuUsage, 1)
        $usedPercent = [math]::Round(($usedMem / $totalMem) * 100, 1)

        # --- GPU VRAM (Nvidia / AMD / Intel) ---
        $gpuMemoryLine = ""
        try {
            # --- Nvidia ---
            $nvidiaSmi = Get-Command "nvidia-smi" -ErrorAction SilentlyContinue
            if ($nvidiaSmi) {
                $smiOutput = & nvidia-smi
                $memLine = $smiOutput | Select-String -Pattern '(\d+)MiB\s*/\s*(\d+)MiB'
                if ($memLine) {
                    $vramUsed = [int]$memLine.Matches[0].Groups[1].Value
                    $vramTotal = [int]$memLine.Matches[0].Groups[2].Value
                    $vramPercent = [math]::Round(($vramUsed / $vramTotal) * 100, 1)
                    $gpuMemoryLine = " | VRAM: $vramUsed MB / $vramTotal MB ($vramPercent%)"
                }
                else {
                    $gpuMemoryLine = " | VRAM: parse failed"
                }
            }
            # --- AMD / Intel (via WMI) ---
            else {
                $gpuInfo = Get-CimInstance -ClassName Win32_VideoController | Select-Object -First 1
                if ($gpuInfo) {
                    $vramTotal = [math]::Round($gpuInfo.AdapterRAM / 1MB, 0)

                    # Dedicated VRAM used via counter (AMD/Intel support varies)
                    $vramUsedRaw = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction SilentlyContinue)
                    if ($vramUsedRaw) {
                        $vramUsed = [math]::Round(($vramUsedRaw.CounterSamples | Measure-Object CookedValue -Sum).Sum / 1MB, 0)
                        $vramPercent = [math]::Round(($vramUsed / $vramTotal) * 100, 1)
                        $gpuMemoryLine = " | VRAM: $vramUsed MB / $vramTotal MB ($vramPercent%)"
                    }
                    else {
                        # Fallback: total VRAM only, usage not available
                        $gpuMemoryLine = " | VRAM: ? MB / $vramTotal MB (usage N/A)"
                    }
                }
                else {
                    $gpuMemoryLine = " | VRAM: No GPU detected"
                }
            }
        }
        catch {
            $gpuMemoryLine = " | VRAM: ERROR - $($_.Exception.Message)"
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $perfLine = "$timestamp | CPU: $cpuPercent% | RAM: $usedMem MB / $([math]::Round($totalMem,0)) MB ($usedPercent%)$gpuMemoryLine"

        # --- Write with retry to avoid file lock / stream conflicts ---
        $maxRetries = 5
        $retryCount = 0
        $written = $false

        while (-not $written -and $retryCount -lt $maxRetries) {
            try {
                [System.IO.File]::AppendAllText($perfLogFile, "$perfLine`r`n")
                $written = $true
            }
            catch [System.IO.IOException] {
                $retryCount++
                Write-Host "File locked, retrying ($retryCount/$maxRetries)..." -ForegroundColor DarkYellow
                Start-Sleep -Milliseconds 200
            }
            catch [System.ArgumentException] {
                # Stream not readable — file may be corrupt/empty, recreate it
                Write-Host "Stream error, recreating log file..." -ForegroundColor DarkYellow
                Remove-Item -Path $perfLogFile -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 100
                $retryCount++
            }
        }

        if (-not $written) {
            Write-Host "WARN: Could not write perf log after $maxRetries retries." -ForegroundColor Red
        }
        else {
            Write-Host "PERF LOGGED: $perfLine" -ForegroundColor Green
        }

        $perfCounter = 0
    }
    else {
        $perfCounter++
    }

    # --- Pause for real-time responsiveness ---
    Start-Sleep -Seconds $checkIntervalSeconds
}