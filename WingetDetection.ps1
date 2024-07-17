#*===============================================
#* Winget Pre-Install Script
#*===============================================
# Folder Variable
$FolderPath = "C:\ProgramData\Pckgr"

# Check if Folder exists
if (!(Test-Path -Path $FolderPath)) {
    New-Item -ItemType Directory -Path $FolderPath -Force
    Write-Host 'New folder created successfully!' -ForegroundColor Green
} else {
    Write-Host 'Folder already exists!' -ForegroundColor Yellow
}

Start-Transcript -Path "C:\ProgramData\Pckgr\Pckgr_WingetPreInstallDetection.txt" -Append -IncludeInvocationHeader
#*===============================================
#* Check Winget
#*===============================================
$exitCode = 0

try {
    # Get the path to the Winget executable(s)
    $wingetPaths = Get-ChildItem 'C:\Program Files\WindowsApps' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'winget.exe' } | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
    
    if ($wingetPaths.Count -gt 1) {
        # Create a dictionary to store the version numbers of each Winget.exe file
        $versions = @{}

        # Loop through each Winget.exe path and extract its version number
        foreach ($path in $wingetPaths) {
            $wingetversion = $path.Split("_")[1]
            if (-not $versions.ContainsKey($wingetversion)) {
                $versions[$wingetversion] = $path
            }
        }

        # Get the latest version number
        $latestVersion = [version]($versions.Keys | Sort-Object -Descending | Select-Object -First 1)
        $versionToFind = "$latestVersion"
        $wingetexe = $versions[$versionToFind]
    } else {
        $wingetexe = $wingetPaths
    }

    if (-not $wingetexe) {
        Write-Error "Winget executable not found."
        $exitCode = 1
    } else {
        $wingettest = & $wingetexe
        if ($wingettest -like "*Windows Package Manager*") {
            Write-Host "Winget Found, checking version"
            $wingetVersion = & $wingetexe --version

            # Removes the leading 'v' and anything following a dash
            $wingetVersion = $wingetVersion -replace '^v|-.+$', ''

            if ([Version]$wingetVersion -ge [Version]'1.6.3482') {
                Write-Host 'Winget is up to date'
                $exitCode = 0
            } else {
                Write-Host 'Winget is not up to date'
                $exitCode = 1
            }
        } else {
            Write-Error 'Winget not Found'
            $exitCode = 1
        }
    }
} catch {
    Write-Error "An error occurred: $_"
    $exitCode = 1
} finally {
    Stop-Transcript
    Exit $exitCode
}
