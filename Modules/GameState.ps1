function Get-ConfiguredGamingSlots {
    param($Config)

    if ($Config.Slots.Gaming) {
        return @($Config.Slots.Gaming)
    }

    return @($Config.Slots.Active)
}

function Get-StoragePath {
    param($Game)

    if ($Game.StoragePath) { return $Game.StoragePath }
    return $Game.FPath
}

function Get-GamePathForSlot {
    param($Game, [string]$Slot)

    if ($Game.ActivePaths -and $Game.ActivePaths.ContainsKey($Slot)) {
        return $Game.ActivePaths[$Slot]
    }

    $propertyName = "{0}Path" -f $Slot
    if ($Game.PSObject.Properties[$propertyName]) {
        return $Game.$propertyName
    }

    if ($Game.EPath) {
        return $Game.EPath -replace '^[A-Za-z]:', ("{0}:" -f $Slot)
    }

    return $null
}

function Get-GameState {
    param($Games, $Config)

    $gamingSlots = Get-ConfiguredGamingSlots $Config

    foreach ($g in $Games) {
        $activeSlot = $null
        $activePath = $null

        foreach ($slot in $gamingSlots) {
            $candidate = Get-GamePathForSlot -Game $g -Slot $slot
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                $activeSlot = $slot
                $activePath = $candidate
                break
            }
        }

        $storagePath = Get-StoragePath $g

        $g | Add-Member -NotePropertyName StoragePath -NotePropertyValue $storagePath -Force

        if ($activePath) {
            $g | Add-Member -NotePropertyName State -NotePropertyValue "Active" -Force
            $g | Add-Member -NotePropertyName ActiveSlot -NotePropertyValue $activeSlot -Force
            $g | Add-Member -NotePropertyName ActivePath -NotePropertyValue $activePath -Force
        }
        elseif ($storagePath -and (Test-Path -LiteralPath $storagePath)) {
            $g | Add-Member -NotePropertyName State -NotePropertyValue "Storage" -Force
            $g | Add-Member -NotePropertyName ActiveSlot -NotePropertyValue $null -Force
            $g | Add-Member -NotePropertyName ActivePath -NotePropertyValue $null -Force
        }
        else {
            $g | Add-Member -NotePropertyName State -NotePropertyValue "Missing" -Force
            $g | Add-Member -NotePropertyName ActiveSlot -NotePropertyValue $null -Force
            $g | Add-Member -NotePropertyName ActivePath -NotePropertyValue $null -Force
        }
    }

    return $Games
}

function Get-GameSize {
    param($Path)

    if (!(Test-Path -LiteralPath $Path)) { return 0 }

    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force |
            Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return $sum
}

function Get-FreeSpace {
    param($DriveLetter)

    return (Get-PSDrive $DriveLetter).Free
}

function Test-StorageCopyMatchesActive {
    param($Game)

    $activeSize = Get-GameSize $Game.ActivePath
    $storageSize = Get-GameSize $Game.StoragePath
    return ($activeSize -gt 0 -and $activeSize -eq $storageSize)
}
