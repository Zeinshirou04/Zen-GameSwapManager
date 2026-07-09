function Show-Header {
    param($Version)

    Clear-Host

    $width = [console]::WindowWidth
    $title = "Zen Game Swap Manager"
    $ver   = "v$Version"

    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host ($title.PadLeft(($width + $title.Length)/2).PadRight($width)) -ForegroundColor Cyan
    Write-Host ($ver.PadLeft(($width + $ver.Length)/2).PadRight($width)) -ForegroundColor Gray
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-DriveStats {
    param($Gaming, $Storage)

    Write-Host ("Configured gaming drives: {0}; storage: {1}:" -f (($Gaming) -join ", "), $Storage) -ForegroundColor Green
    Write-Host ""

    foreach ($driveLetter in @($Gaming) + @($Storage)) {
        $drive = Get-PSDrive $driveLetter
        $free  = [math]::Round($drive.Free/1GB,2)
        $used  = [math]::Round(($drive.Used)/1GB,2)
        $total = [math]::Round(($drive.Used + $drive.Free)/1GB,2)

        Write-Host ("{0,-4} Free {1,8} GB | Used {2,8} GB | Total {3,8} GB" -f "($driveLetter):\", $free, $used, $total) -ForegroundColor White
    }

    Write-Host ""
    Write-Host ("=" * [console]::WindowWidth) -ForegroundColor DarkCyan
}
