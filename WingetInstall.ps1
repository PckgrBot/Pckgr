##*===============================================
##* Check/Install C++ (x64)
##*===============================================
$Apps = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Select-Object -Property DisplayName, DisplayVersion | Sort DisplayName
$AppSelect = $Apps | Where-Object {$_.DisplayName -like '*Microsoft Visual C++ 2015-2022 Redistributable (x64)*'}
if ($AppSelect -eq $null) {
#Install
New-Item -Path 'C:\WingetInstall' -ItemType Directory -Force
Invoke-WebRequest -URI https://download.visualstudio.microsoft.com/download/pr/7331f052-6c2d-4890-8041-8058fee5fb0f/CE6593A1520591E7DEA2B93FD03116E3FC3B3821A0525322B0A430FAA6B3C0B4/VC_redist.x64.exe -OutFile C:\WingetInstall\VC_redist.x64.exe
cmd.exe /c "C:\WingetInstall\VC_redist.x64.exe" /Q /norestart
Remove-Item -Path 'C:\WingetInstall' -Recurse
}
##*===============================================
##* Check/Install C++ (x86)
##*===============================================
$Apps = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Select-Object -Property DisplayName, DisplayVersion | Sort DisplayName
$AppSelect = $Apps | Where-Object {$_.DisplayName -like '*Microsoft Visual C++ 2015-2022 Redistributable (x86)*'}
if ($AppSelect -eq $null) {
#Install
New-Item -Path 'C:\WingetInstall' -ItemType Directory -Force
Invoke-WebRequest -URI https://download.visualstudio.microsoft.com/download/pr/7331f052-6c2d-4890-8041-8058fee5fb0f/CF92A10C62FFAB83B4A2168F5F9A05E5588023890B5C0CC7BA89ED71DA527B0F/VC_redist.x86.exe -OutFile C:\WingetInstall\VC_redist.x86.exe
cmd.exe /c "C:\WingetInstall\VC_redist.x86.exe" /Q /norestart
Remove-Item -Path 'C:\WingetInstall' -Recurse
}
##*===============================================
##* Find Latest Version of Winget
##*===============================================
function getNewestLink($match) {
$uri = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
Write-Verbose "[$((Get-Date).TimeofDay)] Getting information from $uri"
$get = Invoke-RestMethod -uri $uri -Method Get -UseBasicParsing -ErrorAction stop
Write-Verbose "[$((Get-Date).TimeofDay)] getting latest release"
$data = $get[0].assets | Where-Object name -Match $match
return $data.browser_download_url
}

$wingetUrl = getNewestLink("msixbundle")
$wingetLicenseUrl = getNewestLink("License1.xml")



# Add AppxPackage and silently continue on error
function AAP($pkg) {
<#
.SYNOPSIS
Adds an AppxPackage to the system.

.DESCRIPTION
Adds an AppxPackage to the system.
#>
Add-AppxPackage $pkg -ErrorAction SilentlyContinue
}

##*===============================================
##* Download Dependencies
##*===============================================
$url = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.1"
$nupkgFolder = "Microsoft.UI.Xaml.2.7.1.nupkg"
$zipFile = "Microsoft.UI.Xaml.2.7.1.nupkg.zip"
Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $zipFile
Expand-Archive $zipFile

# Determine architecture
if ([Environment]::Is64BitOperatingSystem) {
Write-Host "64-bit OS detected"

# Install x64 VCLibs
AAP("https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx")

# Install x64 XAML
Write-Host "Installing x64 XAML..."
AAP("Microsoft.UI.Xaml.2.7.1.nupkg\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx")
} else {
Write-Host "32-bit OS detected"

# Install x86 VCLibs
AAP("https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx")

# Install x86 XAML
Write-Host "Installing x86 XAML..."
AAP("Microsoft.UI.Xaml.2.7.1.nupkg\tools\AppX\x86\Release\Microsoft.UI.Xaml.2.7.appx")
}

##*===============================================
##* Install Winget
##*===============================================
Write-Host "Installing Winget"
$wingetPath = "winget.msixbundle"
Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath
$wingetLicensePath = "license1.xml"
Invoke-WebRequest -Uri $wingetLicenseUrl -OutFile $wingetLicensePath
Add-AppxProvisionedPackage -Online -PackagePath $wingetPath -LicensePath $wingetLicensePath -ErrorAction SilentlyContinue

# Adding WindowsApps directory to PATH variable for current user
$path = [Environment]::GetEnvironmentVariable("PATH", "User")
$path = $path + ";" + [IO.Path]::Combine([Environment]::GetEnvironmentVariable("LOCALAPPDATA"), "Microsoft", "WindowsApps")
[Environment]::SetEnvironmentVariable("PATH", $path, "User")

##*===============================================
##* Cleanup Files
##*===============================================
Write-Host "Cleaning up..."
Remove-Item $zipFile
Remove-Item $nupkgFolder -Recurse
Remove-Item $wingetPath
Remove-Item $wingetLicensePath


Write-Host "Install has completed successfully!"