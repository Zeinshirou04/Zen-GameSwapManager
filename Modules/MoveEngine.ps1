function Invoke-RobocopyTransfer {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Name,
        $Config,
        [switch]$Move,
        [switch]$Mirror
    )

    $operation = if ($Move) { "Moving" } elseif ($Mirror) { "Backing up" } else { "Copying" }
    Write-Log "$operation $Name from $Source to $Destination"
    Write-Host ("Starting {0}: {1}" -f $operation.ToLowerInvariant(), $Name) -ForegroundColor Cyan

    $retry = $Config.Robocopy.RetryCount
    $wait  = $Config.Robocopy.WaitSeconds
    $mt    = $Config.Robocopy.MultiThread
    $verbose = $Config.Robocopy.Verbose
    if ($null -eq $verbose) { $verbose = $Config.Robocopy.VerboseByDefault }
    if ($null -eq $verbose) { $verbose = $true }
    $verbose = [bool]$verbose

    $args = @(
        $Source
        $Destination
        "/R:$retry"
        "/W:$wait"
        "/MT:$mt"
    )

    if ($Mirror) {
        $args += "/MIR"
    }
    else {
        $args += "/E"
    }

    if ($Move) {
        $args += "/MOVE"
    }

    if (-not $verbose) {
        $args += "/NFL"
        $args += "/NDL"
    }

    $output = robocopy @args
    foreach ($line in $output) {
        if ($verbose) { Write-Host $line }
        Write-Log $line
    }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) {
        $message = "Robocopy failed for $Name with exit code $exitCode"
        Write-Log $message "ERROR"
        throw $message
    }

    Write-Log "$operation completed for $Name"
    Write-Host ("Completed {0}: {1}" -f $operation.ToLowerInvariant(), $Name) -ForegroundColor Green
}

function Move-Game {
    param($Source, $Destination, $Name, $Config)
    Invoke-RobocopyTransfer -Source $Source -Destination $Destination -Name $Name -Config $Config -Move
}

function Copy-Game {
    param($Source, $Destination, $Name, $Config)
    Invoke-RobocopyTransfer -Source $Source -Destination $Destination -Name $Name -Config $Config
}

function Backup-GameToStorage {
    param($Source, $Destination, $Name, $Config)
    Invoke-RobocopyTransfer -Source $Source -Destination $Destination -Name $Name -Config $Config -Mirror
}

function Remove-ActiveGame {
    param($Path, $Name)

    Write-Log "Removing active copy for $Name at $Path"
    Write-Host ("Removing active copy: {0}" -f $Name) -ForegroundColor Yellow
    Remove-Item -LiteralPath $Path -Recurse -Force
    Write-Log "Removed active copy for $Name"
}

function Flush-E {
    param($Games, $Config)

    $activeGames = $Games | Where-Object { $_.State -eq "Active" -or $_.State -eq "E" }

    foreach ($g in $activeGames) {
        Move-Game $g.EPath $g.FPath $g.Name $Config
    }
}
