#Detection of version
$WingetID = '<WINGET ID>'
$Apps = winget list --id $WingetID --exact --accept-source-agreements | Select-String "$WingetID" -SimpleMatch
$AppsOption1 =  $Apps -split ("\s+") | Select-Object -Last 3 | Select-Object -First 1
$AppsOption2 =  $Apps -split ("\s+") | Select-Object -Last 2 | Select-Object -First 1          
$WingetVersion = '<APPLICATION VERSION>'                

#Check to see if application is up to date
if($AppsOption1 -eq $WingetID) 
{
if([Version]$AppsOption2 -ge [Version]$WingetVersion)
{
Write-Output '1'
exit 0
}
}
elseif([Version]$AppsOption1 -ge [Version]$WingetVersion)
{
Write-Output '1'
exit 0
}
else
{
#Specify Launcher App ID
$LauncherID = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
$processName = "notepad++"

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

#Build XML Template
[xml]$ToastTemplate = @"
<toast duration="long">
    <visual>
        <binding template="ToastImageAndText03">
            <text id="1">Update Required for Notepad++</text>
            <text id="2">Please close the Application to start the update.</text>
        </binding>
    </visual>
    <actions>
        <action arguments="ignore" content="Ignore" activationType="foreground"/>
    </actions> 
</toast>
"@


#Prepare XML
$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
$ToastXml.LoadXml($ToastTemplate.OuterXml)

#Prepare and Create Toast
$Toast = [Windows.UI.Notifications.ToastNotification]::New($ToastXml)

if (Get-Process $processName -ErrorAction SilentlyContinue) {

[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($Toast)

    Start-Sleep 60
    if (Get-Process $processName -ErrorAction SilentlyContinue)
    {
        Write-Host 'App is still open.'
    }
    else
    {
        Write-Output 1
    }

}
else
{
Write-Output 1
}

}

