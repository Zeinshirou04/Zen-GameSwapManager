. "$PSScriptRoot\Modules\Logging.ps1"
. "$PSScriptRoot\Modules\GameLoader.ps1"
. "$PSScriptRoot\Modules\GameState.ps1"
. "$PSScriptRoot\Modules\MoveEngine.ps1"
. "$PSScriptRoot\Modules\SwapWorkflow.ps1"

. "$PSScriptRoot\Modules\ConsoleUI.ps1"

$Config = . "$PSScriptRoot\Config.ps1"

Initialize-Logging
$exitCode = 0

try {
    Show-Header -Version $Config.Application.Version
    Show-DriveStats -Gaming (Get-ConfiguredGamingSlots $Config) -Storage $Config.Slots.Storage

    Start-SwapProcess -Config $Config
}
catch {
    $err = $_.Exception.Message
    Write-Log "Fatal error: $err" "ERROR"
    Write-Host "A fatal error occurred: $err" -ForegroundColor Red
    Write-Host "See logs for full details." -ForegroundColor Yellow
    $exitCode = 1
}
finally {
    Write-Host ""
    Write-Host "Press Enter to close..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

exit $exitCode
