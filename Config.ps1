@{
    Slots = @{
        # Gaming drives can both be used for playing games.
        # The copy target is selected per operation based on free space.
        Gaming  = @("D", "E")
        Storage = "O"

        # Backward-compatible alias used by older game configs.
        Active  = "E"
    }

    Safety = @{
        AbortWhenUnmanaged   = $false
        MaxUnmanagedExamples = 5
    }

    Robocopy = @{
        RetryCount  = 2
        WaitSeconds = 2
        MultiThread = 8
        Verbose = $true
        VerboseByDefault = $true
    }

    Logging = @{
        LogFolder = "Logs"
    }

    Application = @{
        Version = "1.5.0"
    }
}
