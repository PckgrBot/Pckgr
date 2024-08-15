#!/bin/sh
# =============================================================================
#  WARNING: Unauthorized Modification Prohibited
#  ----------------------------------------------------------------------------
#  Please note that this script includes security measures designed to detect 
#  and prevent unauthorized use. Any attempts to alter these security features 
#  or to bypass the subscription validation process may result in immediate 
#  termination of service and potential legal action.
#
#  For support or inquiries, please contact Pckgr support at support@intunepckgr.com.
#
#  Thank you for adhering to Pckgr's policies and ensuring the integrity of 
#  our services.
# =============================================================================

# Define the Org ID
ORG_ID="placeholder"

# Call the backend workflow to check subscription status
API_RESPONSE=$(curl -s "https://intunepckgr.com/api/1.1/wf/macos_check?id=$ORG_ID")

# Extract the 'status' value
STATUS=$(echo $API_RESPONSE | sed -n 's/.*"status": "\(.*\)", "response".*/\1/p')

# Extract the 'response' value
SUBSCRIPTION_STATUS=$(echo $API_RESPONSE | sed -n 's/.*"response": { "status": "\(.*\)" }.*/\1/p')


# Check if the subscription is active
if [ "$STATUS" != "success" ] || [ "$SUBSCRIPTION_STATUS" != "active" ]; then
    echo "Subscription inactive or verification failed. Exiting."
    exit 0
fi

LOCKDIR="/tmp/pckgrmac.lock"
MAX_AGE=300  # Maximum age of the lock file in seconds

while ! mkdir "$LOCKDIR" 2>/dev/null; do
    echo "Another instance of the script is running, waiting..."
    
    # Check if the lock directory is too old using find
    LOCK_AGE=$(find "$LOCKDIR" -type d -maxdepth 0 -mtime +$((MAX_AGE / 60)) -print)
    
    if [ -n "$LOCK_AGE" ]; then
        echo "The lock directory is too old. Removing stale lock."
        rm -rf "$LOCKDIR"
        mkdir "$LOCKDIR" 2>/dev/null
        break
    fi
    
    sleep 2  # Wait before checking again
done
# Ensure the lock directory is removed when the script exits
trap 'rm -rf "$LOCKDIR"' EXIT

# Verify that Installomator has been installed
destFile="/usr/local/Installomator/Installomator.sh"
currentInstalledVersion="$(${destFile} version 2>/dev/null || true)"
if [[ ! -e "${destFile}" ]]; then
    printlog "Installomator not found. Installing it now."

    name="Installomator"
    printlog "$name check for installation"
    gitusername="Installomator"
    gitreponame="Installomator"
    filetype="pkg"
    downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
    if [[ "$(echo $downloadURL | grep -ioE "https.*.$filetype")" == "" ]]; then
        printlog "GitHub API failed, trying failover."
        downloadURL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1)" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
    fi
    appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g')
    expectedTeamID="JME5BW3F3R"

    printlog "${destFile} version: $currentInstalledVersion"
    if [[ ! -e "${destFile}" || "$currentInstalledVersion" != "$appNewVersion" ]]; then
        printlog "$name not found or version not latest."
        printlog "${destFile}"
        printlog "Installing version ${appNewVersion} ..."
        tmpDir="$(mktemp -d || true)"
        printlog "Created working directory '$tmpDir'"
        printlog "Downloading $name package version $appNewVersion from: $downloadURL"
        installationCount=0
        exitCode=9
        while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
            curlDownload=$(curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg" || true)
            curlDownloadStatus=$(echo $?)
            if [[ $curlDownloadStatus -ne 0 ]]; then
                printlog "error downloading $downloadURL, with status $curlDownloadStatus"
                printlog "${curlDownload}"
                exitCode=1
            else
                printlog "Download $name success."
                teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
                printlog "Team ID for downloaded package: $teamID"
                if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
                    printlog "$name package verified. Installing package '$tmpDir/$name.pkg'."
                    pkgInstall=$(installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" 2>&1)
                    pkgInstallStatus=$(echo $?)
                    if [[ $pkgInstallStatus -ne 0 ]]; then
                        printlog "ERROR. $name package installation failed."
                        printlog "${pkgInstall}"
                        exitCode=2
                    else
                        printlog "Installing $name package success."
                        exitCode=0
                    fi
                else
                    printlog "ERROR. Package verification failed for $name before package installation could start. Download link may be invalid."
                    exitCode=3
                fi
            fi
            ((installationCount++))
            printlog "$installationCount time(s), exitCode $exitCode"
            if [[ $installationCount -lt 3 ]]; then
                if [[ $exitCode > 0 ]]; then
                    printlog "Sleep a bit before trying download and install again. $installationCount time(s)."
                    printlog "Remove $(rm -fv "$tmpDir/$name.pkg" || true)"
                    sleep 2
                fi
            else
                printlog "Download and install of $name success."
            fi
        done
        printlog "Deleting working directory '$tmpDir' and its contents."
        printlog "Remove $(rm -Rfv "${tmpDir}" || true)"
        if [[ $exitCode != 0 ]]; then
            printlog "ERROR. Installation of $name failed. Aborting."
            # Exit with failure status
            caffexit $exitCode
        else
            printlog "$name version $appNewVersion installed!"
        fi
    else
        printlog "$name version $appNewVersion already found. Perfect!"
    fi
fi

# Check and install Swift Dialog
dialogScriptVersion="10.2"
icon="https://mosylebusinessweb.blob.core.windows.net/envoit-public/logo-envoit-macosappicon.png"
removeOldIcon=0

# Logging function for Dialog
dialog_log_message="Dialog install, v$dialogScriptVersion"
dialog_label="Dialog-v$dialogScriptVersion"

# Helper function to print logs for dialog
dialog_printlog() {
    timestamp=$(date +%F\ %T)
    if [[ "$(whoami)" == "root" ]]; then
        echo "$timestamp :: $dialog_label : $1" | tee -a $log_location
    else
        echo "$timestamp :: $dialog_label : $1"
    fi
}
dialog_printlog "$(date +%F\ %T) : [LOG-BEGIN] ${dialog_log_message}"

# Handling icon for swiftDialog
dialogIconLocation="/Library/Application Support/Dialog/Dialog.png"
if [[ $removeOldIcon -eq 1 ]]; then
    dialog_printlog "Removing old icon first"
    rm "$dialogIconLocation" || true
fi
if [ ! -d "/Library/Application Support/Dialog" ]; then
    dialog_printlog "Dialog folder not existing or is a file, so fixing that."
    dialog_printlog "$(rm -rv "/Library/Application Support/Dialog")"
    dialog_printlog "$(mkdir -p "/Library/Application Support/Dialog")"
fi
dialog_printlog "$(file "/Library/Application Support/Dialog")"
if [[ -n $icon ]]; then
    #dialog_printlog "icon defined, so investigating that for Dialog!"
    if [[ -n "$(file "$dialogIconLocation" | cut -d: -f2 | grep -o "PNG image data")" ]]; then
        #dialog_printlog "$(file "${dialogIconLocation}")"
        #dialog_printlog "swiftDialog icon already exists as PNG file, so continuing..."
    elif [[ "$( echo $icon | cut -d/ -f1 | cut -c 1-4 )" = "http" ]]; then
        dialog_printlog "icon is web-link, downloading..."
        if ! curl -fs "$icon" -o "$dialogIconLocation"; then
            dialog_printlog "ERROR : Downloading $icon failed."
            dialog_printlog "No icon logo for swiftDialog has been set."
        else
            dialog_printlog "Icon for Dialog downloaded/created."
            dialog_printlog "$(file "${dialogIconLocation}")"
            INSTALL=force
        fi
    elif [[ -n "$(file "$icon" | cut -d: -f2 | grep -o "PNG image data")" ]]; then
        dialog_printlog "icon is PNG, can be used directly."
        if cp "${icon}" "$dialogIconLocation"; then
            dialog_printlog "PNG Icon for Dialog copied."
            dialog_printlog "$(file "${dialogIconLocation}")"
            INSTALL=force
        else
            dialog_printlog "ERROR : Copying $icon failed."
            dialog_printlog "No icon logo for swiftDialog has been set."
        fi
    elif [[ -f "$icon" && -n "$(echo $icon | rev | cut -d. -f1 | rev | grep -oE "(icns|tif|tiff|gif|jpg|jpeg|heic)")" ]]; then
        dialog_printlog "icon is $(echo $icon | rev | cut -d. -f1 | rev), converting..."
        dialog_printlog "$(file "${icon}")"
        if ! sips -s format png "${icon}" --out "$dialogIconLocation"; then
            dialog_printlog "ERROR : Converting $icon failed."
            dialog_printlog "No icon logo for swiftDialog has been set."
        else
            dialog_printlog "Icon for Dialog converted."
            dialog_printlog "$(file "${dialogIconLocation}")"
            INSTALL=force
        fi
    else
        dialog_printlog "Icon situation not handled."
        dialog_printlog "No icon logo for swiftDialog has been set."
    fi
else
    dialog_printlog "icon not defined."
fi
dialog_printlog "INSTALL=${INSTALL}"

# Install Swift Dialog
name="Dialog"
#dialog_printlog "$name check for installation"
gitusername="swiftDialog"
gitreponame="swiftDialog"
filetype="pkg"
downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
if [[ "$(echo $downloadURL | grep -ioE "https.*.$filetype")" == "" ]]; then
    dialog_printlog "WARN  : GitHub API failed, trying failover."
    downloadURL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1)" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
fi
appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g')
expectedTeamID="PWA5E9TQ59"
dialog_destFile="/Library/Application Support/Dialog/Dialog.app"
versionKey="CFBundleShortVersionString"
currentInstalledVersion="$(/usr/libexec/PlistBuddy -c "Print :$versionKey" "${dialog_destFile}/Contents/Info.plist" | tr -d "[:special:]" || true)"
dialog_printlog "${name} version installed: $currentInstalledVersion"

destFile2="/usr/local/bin/dialog"
if [[ ! -d "${dialog_destFile}" || ! -x "${destFile2}" || "$currentInstalledVersion" != "$appNewVersion" || "$INSTALL" == "force" ]]; then
    dialog_printlog "$name not found, version not latest, icon for Dialog was changed."
    dialog_printlog "${dialog_destFile}"
    dialog_printlog "Installing version ${appNewVersion}…"
    tmpDir="$(mktemp -d || true)"
    dialog_printlog "Created working directory '$tmpDir'"
    dialog_printlog "Downloading $name package version $appNewVersion from: $downloadURL"
    installationCount=0
    exitCode=9
    while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
        curlDownload=$(curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg" || true)
        curlDownloadStatus=$(echo $?)
        if [[ $curlDownloadStatus -ne 0 ]]; then
            dialog_printlog "ERROR : Error downloading $downloadURL, with status $curlDownloadStatus"
            dialog_printlog "${curlDownload}"
            exitCode=1
        else
            dialog_printlog "Download $name success."
            teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
            dialog_printlog "Team ID for downloaded package: $teamID"
            if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
                dialog_printlog "$name package verified. Installing package '$tmpDir/$name.pkg'."
                pkgInstall=$(installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" 2>&1)
                pkgInstallStatus=$(echo $?)
                if [[ $pkgInstallStatus -ne 0 ]]; then
                    dialog_printlog "ERROR : $name package installation failed."
                    dialog_printlog "${pkgInstall}"
                    exitCode=2
                else
                    dialog_printlog "Installing $name package success."
                    exitCode=0
                fi
            else
                dialog_printlog "ERROR : Package verification failed for $name before package installation could start. Download link may be invalid."
                exitCode=3
            fi
        fi
        ((installationCount++))
        dialog_printlog "$installationCount time(s), exitCode $exitCode"
        if [[ $installationCount -lt 3 ]]; then
            if [[ $exitCode -gt 0 ]]; then
                dialog_printlog "Sleep a bit before trying download and install again. $installationCount time(s)."
                dialog_printlog "Remove $(rm -fv "$tmpDir/$name.pkg" || true)"
                sleep 2
            fi
        else
            dialog_printlog "Download and install of $name success."
        fi
    done
    dialog_printlog "Deleting working directory '$tmpDir' and its contents."
    dialog_printlog "Remove $(rm -Rfv "${tmpDir}" || true)"
    if [[ $exitCode != 0 ]]; then
        dialog_printlog "ERROR : Installation of $name failed. Aborting."
    else
        dialog_printlog "$name version $appNewVersion installed!"
    fi
else
    dialog_printlog "$name version $appNewVersion already found. Perfect!"
fi

dialog_printlog "$(date +%F\ %T) : [LOG-END] ${dialog_log_message}"

# Continue with Installomator script


LOGO="microsoft"

item=""

# Dialog icon and overlay icon
icon=""
overlayicon=""

# dockutil variables
addToDock="0" # with dockutil after installation (0 if not)
appPath=""

# Other variables
dialog_command_file="/var/tmp/dialog.log"
dialogBinary="/usr/local/bin/dialog"
dockutil="/usr/local/bin/dockutil"
installomatorOptions="BLOCKING_PROCESS_ACTION=prompt_user DIALOG_CMD_FILE=${dialog_command_file}" # Separated by space
scriptVersion="10.5"
# PATH declaration
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
echo "$(date +%F\ %T) [LOG-BEGIN] $item, v$scriptVersion"
dialogUpdate() {
    # $1: dialog command
    local dcommand="$1"

    if [[ -n $dialog_command_file ]]; then
        echo "$dcommand" >> "$dialog_command_file"
        echo "Dialog: $dcommand"
    fi
}
checkCmdOutput () {
    local checkOutput="$1"
    exitStatus="$( echo "${checkOutput}" | grep --binary-files=text -i "exit" | tail -1 | sed -E 's/.*exit code ([0-9]).*/\1/g' || true )"
    if [[ ${exitStatus} -eq 0 ]] ; then
        echo "${item} succesfully installed."
        selectedOutput="$( echo "${checkOutput}" | grep --binary-files=text -E ": (REQ|ERROR|WARN)" || true )"
        echo "$selectedOutput"
    else
        echo "ERROR installing ${item}. Exit code ${exitStatus}"
        echo "$checkOutput"
        #errorOutput="$( echo "${checkOutput}" | grep --binary-files=text -i "error" || true )"
        #echo "$errorOutput"
    fi
    #echo "$checkOutput"
}

# Check the currently logged in user
currentUser=$(stat -f "%Su" /dev/console)
if [ -z "$currentUser" ] || [ "$currentUser" = "loginwindow" ] || [ "$currentUser" = "_mbsetupuser" ] || [ "$currentUser" = "root" ]; then
    echo "ERROR. Logged in user is $currentUser! Cannot proceed."
    exit 97
fi
# Get the current user's UID for dockutil
uid=$(id -u "$currentUser")
# Find the home folder of the user
userHome="$(dscl . -read /users/${currentUser} NFSHomeDirectory | awk '{print $2}')"

# Verify that Installomator has been installed
destFile="/usr/local/Installomator/Installomator.sh"
if [ ! -e "${destFile}" ]; then
    echo "Installomator not found here:"
    echo "${destFile}"
    echo "Exiting."
    exit 99
fi

# No sleeping
/usr/bin/caffeinate -d -i -m -u &
caffeinatepid=$!
caffexit () {
    kill "$caffeinatepid"
    exit $1
}

# Mark: Installation begins
installomatorVersion="$(${destFile} version | cut -d "." -f1 || true)"

if [[ $installomatorVersion -lt 10 ]] || [[ $(sw_vers -buildVersion | cut -c1-2) -lt 20 ]]; then
    echo "Skipping swiftDialog UI, using notifications."
    #echo "Installomator should be at least version 10 to support swiftDialog. Installed version $installomatorVersion."
    #echo "And macOS 11 Big Sur (build 20A) is required for swiftDialog. Installed build $(sw_vers -buildVersion)."
    installomatorNotify="NOTIFY=all"
else
    installomatorNotify="NOTIFY=silent"
    # check for Swift Dialog
    if [[ ! -x $dialogBinary ]]; then
        echo "Cannot find dialog at $dialogBinary"
        # Install using Installlomator
        cmdOutput="$(${destFile} dialog LOGO=$LOGO BLOCKING_PROCESS_ACTION=ignore LOGGING=REQ NOTIFY=silent || true)"
        checkCmdOutput "${cmdOutput}"
    fi

    # Configure and display swiftDialog
    itemName=$( ${destFile} ${item} RETURN_LABEL_NAME=1 LOGGING=REQ INSTALL=force | tail -1 || true )
    if [[ "$itemName" != "#" ]]; then
        message="Installing ${itemName}…"
    else
        message="Installing ${item}…"
    fi
    echo "$item $itemName"

    #Check icon (expecting beginning with “http” to be web-link and “/” to be disk file)
    #echo "icon before check: $icon"
    if [[ "$(echo ${icon} | grep -iE "^(http|ftp).*")" != ""  ]]; then
        #echo "icon looks to be web-link"
        if ! curl -sfL --output /dev/null -r 0-0 "${icon}" ; then
            echo "ERROR: Cannot download ${icon} link. Reset icon."
            icon=""
        fi
    elif [[ "$(echo ${icon} | grep -iE "^\/.*")" != "" ]]; then
        #echo "icon looks to be a file"
        if [[ ! -a "${icon}" ]]; then
            echo "ERROR: Cannot find icon file ${icon}. Reset icon."
            icon=""
        fi
    else
        echo "ERROR: Cannot figure out icon ${icon}. Reset icon."
        icon=""
    fi
    #echo "icon after first check: $icon"
    # If no icon defined we are trying to search for installed app icon
    if [[ "$icon" == "" ]]; then
        appPath=$(mdfind "kind:application AND name:$itemName" | head -1 || true)
        appIcon=$(defaults read "${appPath}/Contents/Info.plist" CFBundleIconFile || true)
        if [[ "$(echo "$appIcon" | grep -io ".icns")" == "" ]]; then
            appIcon="${appIcon}.icns"
        fi
        icon="${appPath}/Contents/Resources/${appIcon}"
        #echo "Icon before file check: ${icon}"
        if [ ! -f "${icon}" ]; then
            # Using LOGO variable to show logo in swiftDialog
            case $LOGO in
                appstore)
                    # Apple App Store on Mac
                    if [[ $(sw_vers -buildVersion) > "19" ]]; then
                        LOGO_PATH="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
                    else
                        LOGO_PATH="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
                    fi
                    ;;
                jamf)
                    # Jamf Pro
                    LOGO_PATH="/Library/Application Support/JAMF/Jamf.app/Contents/Resources/AppIcon.icns"
                    ;;
                mosyleb)
                    # Mosyle Business
                    LOGO_PATH="/Applications/Self-Service.app/Contents/Resources/AppIcon.icns"
                    ;;
                mosylem)
                    # Mosyle Manager (education)
                    LOGO_PATH="/Applications/Manager.app/Contents/Resources/AppIcon.icns"
                    ;;
                addigy)
                    # Addigy
                    LOGO_PATH="/Library/Addigy/macmanage/MacManage.app/Contents/Resources/atom.icns"
                    ;;
                microsoft)
                    # Microsoft Endpoint Manager (Intune)
                    LOGO_PATH="/Library/Intune/Microsoft Intune Agent.app/Contents/Resources/AppIcon.icns"
                    ;;
                ws1)
                    # Workspace ONE (AirWatch)
                    LOGO_PATH="/Applications/Workspace ONE Intelligent Hub.app/Contents/Resources/AppIcon.icns"
                    ;;
                kandji)
                    # Kandji
                    LOGO="/Applications/Kandji Self Service.app/Contents/Resources/AppIcon.icns"
                    ;;
                filewave)
                    # FileWave
                    LOGO="/usr/local/sbin/FileWave.app/Contents/Resources/fwGUI.app/Contents/Resources/kiosk.icns"
                    ;;
            esac
            if [[ ! -a "${LOGO_PATH}" ]]; then
                echo "ERROR in LOGO_PATH '${LOGO_PATH}', setting Mac App Store."
                if [[ $(/usr/bin/sw_vers -buildVersion) > "19" ]]; then
                    LOGO_PATH="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
                else
                    LOGO_PATH="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
                fi
            fi
            icon="${LOGO_PATH}"
        fi
    fi
    echo "LOGO: $LOGO"
    echo "icon: ${icon}"

    # display first screen
    dialogCMD=("$dialogBinary"
           --title none
           --icon "$icon"
           --message "$message"
           --mini
           --progress 100
           --position bottomright
           --moveable
           --commandfile "$dialog_command_file"
    )

    if [[ -n "$overlayicon" ]]; then
        dialogCMD+=("--overlayicon" ${overlayicon})
    fi

    echo "dialogCMD: ${dialogCMD[*]}"

    "${dialogCMD[@]}" &

    echo "$(date +%F\ %T) : SwiftDialog started!"

    # give everything a moment to catch up
    sleep 0.1
fi

# Install software using Installomator
cmdOutput="$(${destFile} ${item} LOGO=$LOGO ${installomatorOptions} ${installomatorNotify} || true)"
checkCmdOutput "${cmdOutput}"

# Mark: dockutil stuff
if [[ $addToDock -eq 1 ]]; then
    dialogUpdate "progresstext: Adding to Dock"
    if [[ ! -d $dockutil ]]; then
        echo "Cannot find dockutil at $dockutil, trying installation"
        # Install using Installlomator
        cmdOutput="$(${destFile} dockutil LOGO=$LOGO BLOCKING_PROCESS_ACTION=ignore LOGGING=REQ NOTIFY=silent || true)"
        checkCmdOutput "${cmdOutput}"
    fi
    echo "Adding to Dock"
    $dockutil  --add "${appPath}" "${userHome}/Library/Preferences/com.apple.dock.plist" || true
    sleep 1
else
    echo "Not adding to Dock."
fi

# Mark: Ending
if [[ $installomatorVersion -ge 10 && $(sw_vers -buildVersion | cut -c1-2) -ge 20 ]]; then
    # close and quit dialog
    dialogUpdate "progress: complete"
    dialogUpdate "progresstext: Done"

    # pause a moment
    sleep 0.5

    dialogUpdate "quit:"
    sleep 0.5
    #killall "Dialog" 2>/dev/null || true
fi

echo "[$(DATE)][LOG-END]"

caffexit $exitStatus
