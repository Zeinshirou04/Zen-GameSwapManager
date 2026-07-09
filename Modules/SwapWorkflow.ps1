function Get-UnmanagedActiveEntries {
    param($Games, $Config)

    $gamingSlots = Get-ConfiguredGamingSlots $Config
    $managedEPaths = @($Games |
        ForEach-Object {
            $game = $_
            foreach ($slot in $gamingSlots) {
                $path = Get-GamePathForSlot -Game $game -Slot $slot
                if ($path) { $path.ToLowerInvariant() }
            }
        })

    $roots = @($Games |
        ForEach-Object {
            $game = $_
            foreach ($slot in $gamingSlots) {
                $path = Get-GamePathForSlot -Game $game -Slot $slot
                if ($path) { Split-Path $path -Parent }
            }
        } |
        Sort-Object -Unique)

    $unmanaged = @()

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)
        foreach ($dir in $dirs) {
            if ($dir.FullName.ToLowerInvariant() -notin $managedEPaths) {
                $unmanaged += $dir.FullName
            }
        }
    }

    return @($unmanaged | Sort-Object -Unique)
}

function Show-Status {
    param($Games)

    Write-Host ""
    Write-Host ("=" * 52) -ForegroundColor DarkCyan
    Write-Host "Active Games on Gaming Drives:" -ForegroundColor Cyan
    Write-Host ("=" * 52) -ForegroundColor DarkCyan

    $active = @($Games | Where-Object { $_.State -eq "Active" -or $_.State -eq "E" })

    if ($active.Count -eq 0) {
        Write-Host "  (No active games)" -ForegroundColor DarkGray
    }
    else {
        foreach ($g in $active) {
            $size = [math]::Round(($g.SizeBytes / 1GB), 2)
            Write-Host ("  - {0} [{1}:] ({2}GB)" -f $g.Name, $g.ActiveSlot, $size) -ForegroundColor White
        }
    }

    Write-Host ""
}

function Select-Game {
    param($Games)

    $stored = @($Games | Where-Object { $_.State -eq "Storage" -or $_.State -eq "F" })

    if ($stored.Count -eq 0) {
        Write-Host ""
        Write-Host "No games available in storage." -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host "       Available Games (Storage)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host ""

    for ($i = 0; $i -lt $stored.Count; $i++) {
        $size = [math]::Round(($stored[$i].SizeBytes / 1GB), 2)
        $name = $stored[$i].Name
        Write-Host ("  [{0}]  {1,-25} {2,8} GB" -f ($i + 1), $name, $size) -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Please choose the number of the game you want to play (Q to quit):" -ForegroundColor Green
    Write-Host -NoNewline "> " -ForegroundColor Cyan

    $choice = Read-Host

    if ($choice.ToUpper() -eq "Q") {
        return $null
    }

    if (-not ($choice -match '^\d+$')) {
        throw "Invalid selection '$choice'."
    }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $stored.Count) {
        throw "Selection '$choice' is out of range."
    }

    return $stored[$index]
}

function Select-AdditionalGames {
    param(
        [array]$Candidates,
        [long]$RemainingCapacity
    )

    if ($Candidates.Count -eq 0 -or $RemainingCapacity -le 0) {
        return [pscustomobject]@{
            Cancelled = $false
            Selected  = @()
        }
    }

    $selected = @()
    $remaining = $RemainingCapacity

    while ($true) {
        $available = @($Candidates | Where-Object {
            $_.Name -notin $selected.Name -and $_.SizeBytes -le $remaining
        })

        if ($available.Count -eq 0) {
            break
        }

        Write-Host ""
        Write-Host ("Remaining capacity: {0} GB" -f ([math]::Round($remaining / 1GB, 2))) -ForegroundColor Cyan
        Write-Host "Select additional games in order using comma-separated numbers (example: 1,3,2)." -ForegroundColor Green
        Write-Host "Type S to skip adding more games, press Enter to continue, or C to cancel."
        Write-Host ""

        for ($i = 0; $i -lt $available.Count; $i++) {
            $size = [math]::Round(($available[$i].SizeBytes / 1GB), 2)
            Write-Host ("[{0}] {1,-25} {2,8} GB" -f ($i + 1), $available[$i].Name, $size)
        }

        $input = (Read-Host ">").Trim()
        if ($input.ToUpper() -eq "S") {
            break
        }

        if ([string]::IsNullOrWhiteSpace($input)) {
            break
        }

        if ($input.ToUpper() -eq "C") {
            Write-Host "Operation cancelled."
            Write-Log "Operation cancelled during additional selection"
            return [pscustomobject]@{
                Cancelled = $true
                Selected  = @()
            }
        }

        $tokens = @($input -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        if ($tokens.Count -eq 0) {
            Write-Host "No valid numbers were provided." -ForegroundColor Yellow
            continue
        }

        $batch = @()
        $batchNames = @{}
        $batchTotal = 0
        $hasInvalid = $false

        foreach ($token in $tokens) {
            if (-not ($token -match '^\d+$')) {
                Write-Host ("Invalid value '{0}'. Use only numbers separated by commas." -f $token) -ForegroundColor Yellow
                $hasInvalid = $true
                break
            }

            $index = [int]$token - 1
            if ($index -lt 0 -or $index -ge $available.Count) {
                Write-Host ("Selection '{0}' is out of range." -f $token) -ForegroundColor Yellow
                $hasInvalid = $true
                break
            }

            $choice = $available[$index]
            if ($batchNames.ContainsKey($choice.Name)) {
                Write-Host ("'{0}' is duplicated in this input. Keep each number only once." -f $choice.Name) -ForegroundColor Yellow
                $hasInvalid = $true
                break
            }

            $batchNames[$choice.Name] = $true
            $batch += $choice
            $batchTotal += $choice.SizeBytes
        }

        if ($hasInvalid) {
            continue
        }

        if ($batchTotal -gt $remaining) {
            Write-Host ("Selected games exceed remaining capacity ({0} GB)." -f ([math]::Round($remaining / 1GB, 2))) -ForegroundColor Yellow
            continue
        }

        $selected += $batch
        $remaining -= $batchTotal
        Write-Host ("Added {0} game(s) to copy plan." -f $batch.Count) -ForegroundColor Green
    }

    return [pscustomobject]@{
        Cancelled = $false
        Selected  = @($selected)
    }
}

function Invoke-MoveWithRecovery {
    param(
        $Source,
        $Destination,
        $Name,
        $Config
    )

    while ($true) {
        try {
            Move-Game -Source $Source -Destination $Destination -Name $Name -Config $Config
            return $true
        }
        catch {
            $errorText = $_.Exception.Message
            Write-Host ""
            Write-Host ("Move failed for '{0}': {1}" -f $Name, $errorText) -ForegroundColor Red
            Write-Host "Fix the issue (close game/launcher, free space, permissions) then choose:" -ForegroundColor Yellow
            Write-Host "  CONTINUE = retry move  |  SKIP = skip this game  |  ABORT = stop operation"

            $action = (Read-Host "> ").Trim().ToUpper()

            switch ($action) {
                "CONTINUE" {
                    Write-Log "Continue requested for $Name after failure"
                    continue
                }
                "SKIP" {
                    Write-Log "Skipped move for $Name after failure" "WARN"
                    return $false
                }
                "ABORT" {
                    throw "Operation aborted by user after move failure for $Name"
                }
                default {
                    Write-Host "Invalid option. Type CONTINUE, SKIP, or ABORT." -ForegroundColor Yellow
                }
            }
        }
    }
}


function Invoke-CopyWithRecovery {
    param(
        $Source,
        $Destination,
        $Name,
        $Config
    )

    while ($true) {
        try {
            Copy-Game -Source $Source -Destination $Destination -Name $Name -Config $Config
            return $true
        }
        catch {
            $errorText = $_.Exception.Message
            Write-Host ""
            Write-Host ("Copy failed for '{0}': {1}" -f $Name, $errorText) -ForegroundColor Red
            Write-Host "Fix the issue (free space, permissions) then choose:" -ForegroundColor Yellow
            Write-Host "  CONTINUE = retry copy  |  SKIP = skip this game  |  ABORT = stop operation"

            $action = (Read-Host "> ").Trim().ToUpper()

            switch ($action) {
                "CONTINUE" {
                    Write-Log "Continue requested for $Name after copy failure"
                    continue
                }
                "SKIP" {
                    Write-Log "Skipped copy for $Name after failure" "WARN"
                    return $false
                }
                "ABORT" {
                    throw "Operation aborted by user after copy failure for $Name"
                }
                default {
                    Write-Host "Invalid option. Type CONTINUE, SKIP, or ABORT." -ForegroundColor Yellow
                }
            }
        }
    }
}


function Select-TargetGamingDrive {
    param(
        $Config,
        [array]$ActiveGames,
        [long]$RequiredBytes
    )

    $gamingSlots = Get-ConfiguredGamingSlots $Config

    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host "       Choose Gaming Drive Target" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor DarkCyan

    for ($i = 0; $i -lt $gamingSlots.Count; $i++) {
        $slot = $gamingSlots[$i]
        $free = Get-FreeSpace $slot
        $verifiedRemovable = @($ActiveGames | Where-Object {
            $_.ActiveSlot -eq $slot -and (Test-StorageCopyMatchesActive -Game $_)
        })
        $removableSize = ($verifiedRemovable | Measure-Object SizeBytes -Sum).Sum
        if ($null -eq $removableSize) { $removableSize = 0 }
        $usable = $free + $removableSize
        $fits = if ($RequiredBytes -le $usable) { "fits" } else { "not enough" }

        Write-Host ("[{0}] {1}: Free {2,8:N2} GB | Usable after verified delete {3,8:N2} GB | {4}" -f ($i + 1), $slot, ($free / 1GB), ($usable / 1GB), $fits)
    }

    Write-Host ""
    Write-Host "Choose the drive to copy the game to (Q to cancel):" -ForegroundColor Green
    $choice = (Read-Host ">").Trim()

    if ($choice.ToUpper() -eq "Q") { return $null }
    if (-not ($choice -match '^\d+$')) { throw "Invalid drive selection '$choice'." }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $gamingSlots.Count) { throw "Drive selection '$choice' is out of range." }

    return $gamingSlots[$index]
}

function Select-ActiveGameForRemoval {
    param($Games)

    $active = @($Games | Where-Object { $_.State -eq "Active" -or $_.State -eq "E" })
    if ($active.Count -eq 0) {
        Write-Host "No active games are available to remove." -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host "       Active Games to Remove" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor DarkCyan

    for ($i = 0; $i -lt $active.Count; $i++) {
        $size = [math]::Round(($active[$i].SizeBytes / 1GB), 2)
        Write-Host ("[{0}] {1,-25} {2}: {3,8} GB" -f ($i + 1), $active[$i].Name, $active[$i].ActiveSlot, $size)
    }

    Write-Host ""
    Write-Host "Choose the active game to remove (Q to cancel):" -ForegroundColor Green
    $choice = (Read-Host ">").Trim()

    if ($choice.ToUpper() -eq "Q") { return $null }
    if (-not ($choice -match '^\d+$')) { throw "Invalid selection '$choice'." }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $active.Count) { throw "Selection '$choice' is out of range." }

    return $active[$index]
}

function Invoke-RemoveOnlyProcess {
    param($Config)

    Write-Log "Remove-only operation started"

    $games = Get-Games $Config
    $games = Get-GameState $games $Config

    foreach ($g in $games) {
        $sizePath = if ($g.State -eq "Active" -or $g.State -eq "E") { $g.ActivePath } else { $g.StoragePath }
        $size = Get-GameSize $sizePath
        $g | Add-Member -NotePropertyName SizeBytes -NotePropertyValue $size -Force
    }

    $selected = Select-ActiveGameForRemoval $games
    if ($null -eq $selected) { return }

    if (-not (Test-StorageCopyMatchesActive -Game $selected)) {
        throw "Refusing to remove '$($selected.Name)' because storage copy is missing or size does not match active copy."
    }

    Write-Host ""
    Write-Host ("Remove '{0}' from {1}: ? Storage copy on {2}: was verified by size. (Y/N)" -f $selected.Name, $selected.ActiveSlot, $Config.Slots.Storage) -ForegroundColor Yellow
    $confirm = (Read-Host).ToUpper()
    if ($confirm -ne "Y") {
        Write-Host "Remove cancelled."
        Write-Log "Remove-only operation cancelled at confirmation"
        return
    }

    Remove-ActiveGame -Path $selected.ActivePath -Name $selected.Name
    Write-Log "Remove-only operation finished successfully"
    Write-Host "Remove completed successfully." -ForegroundColor Green
}

function Invoke-SwapProcess {
    param($Config)

    Write-Log "Swap operation started"

    $games = Get-Games $Config
    $games = Get-GameState $games $Config

    foreach ($g in $games) {
        $sizePath = if ($g.State -eq "Active" -or $g.State -eq "E") { $g.ActivePath } else { $g.StoragePath }
        $size = Get-GameSize $sizePath
        $g | Add-Member -NotePropertyName SizeBytes -NotePropertyValue $size -Force
    }

    Show-Status $games

    $unmanagedActive = Get-UnmanagedActiveEntries -Games $games -Config $Config
    if ($unmanagedActive.Count -gt 0) {
        $maxExamples = $Config.Safety.MaxUnmanagedExamples
        if ($null -eq $maxExamples -or $maxExamples -lt 1) {
            $maxExamples = 5
        }

        Write-Host "Detected unmanaged folders in active drive that are not mapped in Games/*.ps1:" -ForegroundColor Yellow
        foreach ($path in ($unmanagedActive | Select-Object -First $maxExamples)) {
            Write-Host ("  - {0}" -f $path) -ForegroundColor DarkYellow
        }

        if ($unmanagedActive.Count -gt $maxExamples) {
            Write-Host ("  ... and {0} more" -f ($unmanagedActive.Count - $maxExamples)) -ForegroundColor DarkYellow
        }

        Write-Log ("Unmanaged active folders detected: {0}" -f ($unmanagedActive -join "; ")) "WARN"

        if ($Config.Safety.AbortWhenUnmanaged) {
            throw "Unmanaged active folders were detected. Add them to Games definitions or set Safety.AbortWhenUnmanaged = `$false."
        }
    }

    $selected = Select-Game $games
    if ($null -eq $selected) {
        Write-Log "User exited without selecting a game"
        Write-Host "No game selected."
        return
    }

    $currentEGames = @($games | Where-Object { $_.State -eq "Active" -or $_.State -eq "E" })
    $installTarget = Select-TargetGamingDrive -Config $Config -ActiveGames $currentEGames -RequiredBytes $selected.SizeBytes
    if ($null -eq $installTarget) { return }

    $currentFree = Get-FreeSpace $installTarget
    $targetActiveGames = @($currentEGames | Where-Object { $_.ActiveSlot -eq $installTarget })
    $selected | Add-Member -NotePropertyName InstallPath -NotePropertyValue (Get-GamePathForSlot -Game $selected -Slot $installTarget) -Force

    $eSize = ($targetActiveGames | Measure-Object SizeBytes -Sum).Sum
    if ($null -eq $eSize) { $eSize = 0 }

    $capacity = $currentFree + $eSize

    $selectedSize = $selected.SizeBytes

    if ($selectedSize -gt $capacity) {
        throw ("Selected game cannot fit into {0}:. Needed {1:N2} GB, available {2:N2} GB." -f $installTarget, ($selectedSize / 1GB), ($capacity / 1GB))
    }

    $toMove = @($selected)
    $remaining = $capacity - $selectedSize

    $additionalCandidates = @($games |
        Where-Object {
            $_.State -eq "Storage" -and
            $_.Name -notin $toMove.Name
        })

    $additionalResult = Select-AdditionalGames -Candidates $additionalCandidates -RemainingCapacity $remaining
    if ($additionalResult.Cancelled) {
        return
    }

    $additional = @($additionalResult.Selected)
    if ($additional.Count -gt 0) {
        foreach ($g in $additional) {
            $g | Add-Member -NotePropertyName InstallPath -NotePropertyValue (Get-GamePathForSlot -Game $g -Slot $installTarget) -Force
        }
        $toMove += $additional
    }

    Write-Host ""
    Write-Host ("=" * 52) -ForegroundColor DarkCyan
    Write-Host "Planned Copies:" -ForegroundColor Cyan
    Write-Host ("=" * 52) -ForegroundColor DarkCyan

    foreach ($g in $toMove) {
        $size = [math]::Round(($g.SizeBytes / 1GB), 2)
        Write-Host (" - {0} ({1}GB)" -f $g.Name, $size)
    }

    Write-Host ""
    Write-Host "Ready to execute copy/delete plan." -ForegroundColor Green
    Write-Host "Proceed? (Y/N)"
    $confirm = (Read-Host).ToUpper()

    if ($confirm -ne "Y") {
        Write-Host "Operation cancelled."
        Write-Log "Operation cancelled at confirmation"
        return
    }

    $requiredSpace = ($toMove | Measure-Object SizeBytes -Sum).Sum - $currentFree
    if ($requiredSpace -lt 0) { $requiredSpace = 0 }

    $toFlush = @()

    if ($requiredSpace -gt 0) {
        $freed = 0
        foreach ($g in ($targetActiveGames | Sort-Object SizeBytes -Descending)) {
            if ($g.Name -in $toFlush.Name) { continue }
            if (-not (Test-StorageCopyMatchesActive -Game $g)) { continue }

            $toFlush += $g
            $freed += $g.SizeBytes
            if ($freed -ge $requiredSpace) { break }
        }

        if ($freed -lt $requiredSpace) {
            throw ("Unable to free enough space in {0}: for selected copies." -f $installTarget)
        }
    }

    Write-Host ""
    Write-Host ("=" * 52) -ForegroundColor DarkCyan
    Write-Host "Execution started. Please wait..." -ForegroundColor Green
    Write-Host ("Delete verified active copies : {0} game(s)" -f $toFlush.Count) -ForegroundColor Gray
    Write-Host ("Copy from storage to {0}: {1} game(s)" -f $installTarget, $toMove.Count) -ForegroundColor Gray
    Write-Host ("=" * 52) -ForegroundColor DarkCyan

    $flushIndex = 0
    foreach ($g in $toFlush) {
        $flushIndex++
        Write-Host ("[Delete {0}/{1}] {2}" -f $flushIndex, $toFlush.Count, $g.Name) -ForegroundColor Yellow
        if (-not (Test-StorageCopyMatchesActive -Game $g)) {
            throw "Refusing to delete '$($g.Name)' because storage copy is missing or size does not match active copy."
        }
        Remove-ActiveGame -Path $g.ActivePath -Name $g.Name
    }

    $moveIndex = 0
    foreach ($g in $toMove) {
        $moveIndex++
        Write-Host ("[Copy  {0}/{1}] {2}" -f $moveIndex, $toMove.Count, $g.Name) -ForegroundColor Cyan
        Invoke-CopyWithRecovery -Source $g.StoragePath -Destination $g.InstallPath -Name $g.Name -Config $Config | Out-Null
    }

    Write-Log "Copy/delete operation finished successfully"
    Write-Host ""
    Write-Host ("=" * 52) -ForegroundColor DarkCyan
    Write-Host "Operation completed successfully." -ForegroundColor Green
    Write-Host ("=" * 52) -ForegroundColor DarkCyan
}

function Get-GameConfigFiles {
    $gameFolder = Join-Path $PSScriptRoot "..\Games"
    if (-not (Test-Path -LiteralPath $gameFolder)) {
        return @()
    }

    $files = @(Get-ChildItem -LiteralPath $gameFolder -File | Where-Object { $_.Extension -eq ".ps1" -or $_.Extension -eq ".disabled" })
    return @($files | Sort-Object Name)
}

function Show-GameConfigList {
    $files = Get-GameConfigFiles

    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host "              Game Configs" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor DarkCyan

    if ($files.Count -eq 0) {
        Write-Host "No game config files found in Games/." -ForegroundColor Yellow
        return
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
        $status = if ($files[$i].Extension -eq ".ps1") { "ENABLED" } else { "DISABLED" }
        Write-Host ("[{0}] {1,-35} {2}" -f ($i + 1), $files[$i].Name, $status)
    }
}

function Show-ProgramConfig {
    param($Config)

    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host "              Program Config" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor DarkCyan

    Write-Host ("Slots.Gaming                : {0}" -f (($Config.Slots.Gaming) -join ", "))
    Write-Host ("Slots.Storage               : {0}" -f $Config.Slots.Storage)
    Write-Host ("Slots.Active                : {0}" -f $Config.Slots.Active)
    Write-Host ("Safety.AbortWhenUnmanaged   : {0}" -f $Config.Safety.AbortWhenUnmanaged)
    Write-Host ("Safety.MaxUnmanagedExamples : {0}" -f $Config.Safety.MaxUnmanagedExamples)
    Write-Host ("Robocopy.RetryCount         : {0}" -f $Config.Robocopy.RetryCount)
    Write-Host ("Robocopy.WaitSeconds        : {0}" -f $Config.Robocopy.WaitSeconds)
    Write-Host ("Robocopy.MultiThread        : {0}" -f $Config.Robocopy.MultiThread)
    Write-Host ("Robocopy.Verbose            : {0}" -f $Config.Robocopy.Verbose)
    Write-Host ("Robocopy.VerboseByDefault   : {0}" -f $Config.Robocopy.VerboseByDefault)
    Write-Host ("Logging.LogFolder           : {0}" -f $Config.Logging.LogFolder)
    Write-Host ("Application.Version         : {0}" -f $Config.Application.Version)
}

function Convert-ToSafeFileName {
    param([string]$Name)

    $safe = $Name -replace '[^A-Za-z0-9\-_ ]', ''
    $safe = ($safe -replace '\s+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "game_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    }

    return $safe
}

function New-GameConfigFile {
    param(
        [string]$Name,
        [string]$GameFolder,
        [string]$LibraryRelativePath
    )

    $safeFile = Convert-ToSafeFileName -Name $Name
    $gameFolderPath = Join-Path $PSScriptRoot "..\Games"
    $target = Join-Path $gameFolderPath ("{0}.ps1" -f $safeFile)

    if (Test-Path -LiteralPath $target) {
        throw "A config file already exists for '$safeFile'."
    }

    $content = @"
param(`$Config)

`$gamingSlots = Get-ConfiguredGamingSlots `$Config
`$activeAlias = `$Config.Slots.Active
`$storage     = `$Config.Slots.Storage

`$activePaths = @{}
foreach (`$slot in `$gamingSlots) {
    `$root = "`$(`$slot):\\$LibraryRelativePath"
    `$activePaths[`$slot] = Join-Path `$root "$GameFolder"
}

`$activeRoot = "`$(`$activeAlias):\\$LibraryRelativePath"
`$storageRoot = "`$(`$storage):\\$LibraryRelativePath"

@{
    Name        = "$Name"
    ActivePaths = `$activePaths
    EPath       = Join-Path `$activeRoot "$GameFolder"
    FPath       = Join-Path `$storageRoot "$GameFolder"
    StoragePath = Join-Path `$storageRoot "$GameFolder"
}
"@

    Set-Content -LiteralPath $target -Value $content -Encoding UTF8
    Write-Log "Game config created: $($target)"
    Write-Host "Config created: $target" -ForegroundColor Green
}

function Add-GameConfigInteractively {
    Write-Host ""
    Write-Host "Add New Game Config" -ForegroundColor Cyan
    Write-Host "Leave blank to use default library path SteamLibrary\\steamapps\\common"

    $name = (Read-Host "Game display name").Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "Game name is required." -ForegroundColor Yellow
        return
    }

    $folder = (Read-Host "Game folder name (exact directory name)").Trim()
    if ([string]::IsNullOrWhiteSpace($folder)) {
        Write-Host "Game folder name is required." -ForegroundColor Yellow
        return
    }

    $libraryPath = (Read-Host "Library relative path")
    if ([string]::IsNullOrWhiteSpace($libraryPath)) {
        $libraryPath = "SteamLibrary\\steamapps\\common"
    }

    New-GameConfigFile -Name $name -GameFolder $folder -LibraryRelativePath $libraryPath
}

function Select-ConfigFile {
    $files = Get-GameConfigFiles
    if ($files.Count -eq 0) {
        Write-Host "No game config files found." -ForegroundColor Yellow
        return $null
    }

    Show-GameConfigList
    $choice = (Read-Host "Choose config number (or Q)").Trim()
    if ($choice.ToUpper() -eq "Q") {
        return $null
    }

    if (-not ($choice -match '^\d+$')) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return $null
    }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $files.Count) {
        Write-Host "Selection out of range." -ForegroundColor Yellow
        return $null
    }

    return $files[$index]
}

function Toggle-GameConfigState {
    $selected = Select-ConfigFile
    if ($null -eq $selected) {
        return
    }

    if ($selected.Extension -eq ".ps1") {
        $newPath = Join-Path $selected.DirectoryName ($selected.BaseName + ".disabled")
        if (Test-Path -LiteralPath $newPath) {
            throw "Cannot disable config because target file already exists: $newPath"
        }

        Rename-Item -LiteralPath $selected.FullName -NewName ([System.IO.Path]::GetFileName($newPath))
        Write-Log "Config disabled: $($selected.Name)"
        Write-Host "Disabled: $($selected.Name)" -ForegroundColor Green
    }
    else {
        $newPath = Join-Path $selected.DirectoryName ($selected.BaseName + ".ps1")
        if (Test-Path -LiteralPath $newPath) {
            throw "Cannot enable config because target file already exists: $newPath"
        }

        Rename-Item -LiteralPath $selected.FullName -NewName ([System.IO.Path]::GetFileName($newPath))
        Write-Log "Config enabled: $($selected.Name)"
        Write-Host "Enabled: $([System.IO.Path]::GetFileName($newPath))" -ForegroundColor Green
    }
}

function Edit-GameConfigInteractively {
    $selected = Select-ConfigFile
    if ($null -eq $selected) {
        return
    }

    $tempConfig = @{ Slots = @{ Gaming = @("D", "E"); Active = "E"; Storage = "O" } }

    try {
        $gameObj = & $selected.FullName $tempConfig
    }
    catch {
        throw "Unable to load config '$($selected.Name)' for editing."
    }

    $currentName = $gameObj.Name
    $currentFolder = Split-Path $gameObj.EPath -Leaf

    $currentLibraryPath = "SteamLibrary\\steamapps\\common"
    $prefix = "E:\\"
    if ($gameObj.EPath -like "$prefix*") {
        $relative = $gameObj.EPath.Substring($prefix.Length)
        $parts = $relative -split '\\'
        if ($parts.Length -gt 1) {
            $currentLibraryPath = ($parts[0..($parts.Length - 2)] -join "\\")
        }
    }

    Write-Host ""
    Write-Host "Editing $($selected.Name) (leave blank to keep current value)" -ForegroundColor Cyan

    $newName = Read-Host "Game display name [$currentName]"
    if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $currentName }

    $newFolder = Read-Host "Game folder name [$currentFolder]"
    if ([string]::IsNullOrWhiteSpace($newFolder)) { $newFolder = $currentFolder }

    $newLibraryPath = Read-Host "Library relative path [$currentLibraryPath]"
    if ([string]::IsNullOrWhiteSpace($newLibraryPath)) { $newLibraryPath = $currentLibraryPath }

    $content = @"
param(`$Config)

`$gamingSlots = Get-ConfiguredGamingSlots `$Config
`$activeAlias = `$Config.Slots.Active
`$storage     = `$Config.Slots.Storage

`$activePaths = @{}
foreach (`$slot in `$gamingSlots) {
    `$root = "`$(`$slot):\\$newLibraryPath"
    `$activePaths[`$slot] = Join-Path `$root "$newFolder"
}

`$activeRoot = "`$(`$activeAlias):\\$newLibraryPath"
`$storageRoot = "`$(`$storage):\\$newLibraryPath"

@{
    Name        = "$newName"
    ActivePaths = `$activePaths
    EPath       = Join-Path `$activeRoot "$newFolder"
    FPath       = Join-Path `$storageRoot "$newFolder"
    StoragePath = Join-Path `$storageRoot "$newFolder"
}
"@

    Set-Content -LiteralPath $selected.FullName -Value $content -Encoding UTF8
    Write-Log "Config edited: $($selected.Name)"
    Write-Host "Updated: $($selected.Name)" -ForegroundColor Green
}

function Start-SwapProcess {
    param($Config)

    Write-Log "Script started"

    while ($true) {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor DarkCyan
        Write-Host "                 Main Menu" -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor DarkCyan
        Write-Host "[1] Copy game from storage to a gaming drive"
        Write-Host "[2] Remove active game from a gaming drive"
        Write-Host "[3] Enable/Disable game config"
        Write-Host "[4] Add game config"
        Write-Host "[5] Edit existing config"
        Write-Host "[6] View program config"
        Write-Host "[7] View game config list"
        Write-Host "[Q] Quit"

        $choice = (Read-Host "Choose an option").Trim().ToUpper()

        try {
            switch ($choice) {
                "1" { Invoke-SwapProcess -Config $Config }
                "2" { Invoke-RemoveOnlyProcess -Config $Config }
                "3" { Toggle-GameConfigState }
                "4" { Add-GameConfigInteractively }
                "5" { Edit-GameConfigInteractively }
                "6" { Show-ProgramConfig -Config $Config }
                "7" { Show-GameConfigList }
                "Q" {
                    Write-Log "User exited from main menu"
                    return
                }
                default {
                    Write-Host "Invalid option, choose 1-7 or Q." -ForegroundColor Yellow
                }
            }
        }
        catch {
            $errorText = $_.Exception.Message
            Write-Log "Menu operation failed: $errorText" "ERROR"
            Write-Host "Operation failed: $errorText" -ForegroundColor Red
        }
    }
}
