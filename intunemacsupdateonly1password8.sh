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

LOCKDIR="/tmp/pckgrmac.lock"
MAX_AGE=300  # Maximum age of the lock file in seconds

while ! mkdir "$LOCKDIR" 2>/dev/null; do
    LOCK_AGE=$(find "$LOCKDIR" -type d -maxdepth 0 -mtime +$((MAX_AGE / 60)) -print)
    if [ -n "$LOCK_AGE" ]; then
        rm -rf "$LOCKDIR"
        mkdir "$LOCKDIR" 2>/dev/null
        break
    fi
    sleep 2
done
trap 'rm -rf "$LOCKDIR"' EXIT

scriptVersion="9.7"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# --- BEGIN: values your server populates (placeholders preserved) ---
LOGO="microsoft"

# MUST be 1password8 for this custom script
item=""

# MUST be the .app path you want to use for the "update-only" gate
appPath=""

run=""
newappversion=""
icon=""
overlayicon=""
forceupdate=""
enabledialog="false"
# --- END: values your server populates ---

# =============================================================================
# UPDATE-ONLY GATE
# - If the app isn't already installed, exit success (do nothing).
# =============================================================================
if [ -z "${appPath}" ]; then
    echo "appPath is empty, exiting..."
    exit 0
fi

# .app bundles are directories
if [ ! -d "${appPath}" ]; then
    echo "Application not detected at ${appPath}. Exiting (update-only)."
    exit 0
fi

# Mark: Constants, logging and caffeinate
log_message="Installomator update-only, v$scriptVersion"
label="InstUpdate-v$scriptVersion"

log_location="/private/var/log/Installomator.log"
printlog(){
    timestamp=$(date +%F\ %T)
    if [[ "$(whoami)" == "root" ]]; then
        :
        # echo "$timestamp :: $label : $1" | tee -a $log_location
    else
        :
        # echo "$timestamp :: $label : $1"
    fi
}
printlog "[LOG-BEGIN] ${log_message}"

# No sleeping
/usr/bin/caffeinate -d -i -m -u &
caffeinatepid=$!
caffexit () {
    kill "$caffeinatepid" 2>/dev/null || true
    exit "${1:-0}"
}

# =============================================================================
# Install Installomator (pinned)
# =============================================================================
name="Installomator"
specificVersion="10.8"
gitusername="Installomator"
gitreponame="Installomator"
filetype="pkg"
downloadURL="https://github.com/$gitusername/$gitreponame/releases/download/v$specificVersion/Installomator-$specificVersion.pkg"
appNewVersion="$specificVersion"
expectedTeamID="JME5BW3F3R"

destFile="/usr/local/Installomator/Installomator.sh"
currentInstalledVersion="$(${destFile} version 2>/dev/null || true)"
printlog "${destFile} version: $currentInstalledVersion"

if [[ -e "${destFile}" ]]; then
    rm -f "${destFile}" || true
    if [[ -d "/usr/local/Installomator" ]]; then
        rm -rf "/usr/local/Installomator" || true
    fi
fi

tmpDir="$(mktemp -d || true)"
installationCount=0
exitCode=9

while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
    curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg" || true
    curlDownloadStatus=$?
    if [[ $curlDownloadStatus -ne 0 ]]; then
        exitCode=1
    else
        teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
        if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
            installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" >/dev/null 2>&1 || true
            pkgInstallStatus=$?
            if [[ $pkgInstallStatus -ne 0 ]]; then
                exitCode=2
            else
                exitCode=0
            fi
        else
            exitCode=3
        fi
    fi
    ((installationCount++))
    if [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; then
        rm -f "$tmpDir/$name.pkg" || true
        sleep 2
    fi
done

rm -rf "${tmpDir}" 2>/dev/null || true

if [[ $exitCode != 0 ]]; then
    echo "ERROR: Installomator install failed (exitCode=$exitCode)."
    caffexit $exitCode
fi

# =============================================================================
# Install SwiftDialog (same as template)
# =============================================================================
dialogScriptVersion="10.2"
icon="https://mosylebusinessweb.blob.core.windows.net/envoit-public/logo-envoit-macosappicon.png"
removeOldIcon=0

dialog_log_message="Dialog install, v$dialogScriptVersion"
dialog_label="Dialog-v$dialogScriptVersion"

dialog_printlog() {
    timestamp=$(date +%F\ %T)
    if [[ "$(whoami)" == "root" ]]; then
        :
    else
        :
    fi
}

dialogIconLocation="/Library/Application Support/Dialog/Dialog.png"
if [[ $removeOldIcon -eq 1 ]]; then
    rm "$dialogIconLocation" || true
fi
if [ ! -d "/Library/Application Support/Dialog" ]; then
    rm -rv "/Library/Application Support/Dialog" >/dev/null 2>&1 || true
    mkdir -p "/Library/Application Support/Dialog" || true
fi

if [[ -n $icon ]]; then
    if [[ -n "$(file "$dialogIconLocation" | cut -d: -f2 | grep -o "PNG image data")" ]]; then
        :
    elif [[ "$( echo $icon | cut -d/ -f1 | cut -c 1-4 )" = "http" ]]; then
        if curl -fs "$icon" -o "$dialogIconLocation"; then
            INSTALL=force
        fi
    fi
fi

name="Dialog"
gitusername="swiftDialog"
gitreponame="swiftDialog"
filetype="pkg"
downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
if [[ "$(echo $downloadURL | grep -ioE "https.*.$filetype")" == "" ]]; then
    downloadURL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1)" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
fi
appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g')
expectedTeamID="PWA5E9TQ59"
dialog_destFile="/Library/Application Support/Dialog/Dialog.app"
versionKey="CFBundleShortVersionString"
currentInstalledVersion="$(/usr/libexec/PlistBuddy -c "Print :$versionKey" "${dialog_destFile}/Contents/Info.plist" 2>/dev/null | tr -d "[:special:]" || true)"
destFile2="/usr/local/bin/dialog"

if [[ ! -d "${dialog_destFile}" || ! -x "${destFile2}" || "$currentInstalledVersion" != "$appNewVersion" || "$INSTALL" == "force" ]]; then
    tmpDir="$(mktemp -d || true)"
    installationCount=0
    exitCode=9
    while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
        curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg" || true
        curlDownloadStatus=$?
        if [[ $curlDownloadStatus -ne 0 ]]; then
            exitCode=1
        else
            teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
            if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
                installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" >/dev/null 2>&1 || true
                pkgInstallStatus=$?
                if [[ $pkgInstallStatus -ne 0 ]]; then
                    exitCode=2
                else
                    exitCode=0
                fi
            else
                exitCode=3
            fi
        fi
        ((installationCount++))
        if [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; then
            rm -f "$tmpDir/$name.pkg" || true
            sleep 2
        fi
    done
    rm -rf "${tmpDir}" 2>/dev/null || true
    if [[ $exitCode != 0 ]]; then
        echo "ERROR: Dialog install failed (exitCode=$exitCode)."
        caffexit $exitCode
    fi
fi

# =============================================================================
# Main: run Installomator update (with 1Password workaround)
# =============================================================================
dialog_command_file="/var/tmp/dialog.log"
dialogBinary="/usr/local/bin/dialog"

if [ "$forceupdate" = "true" ]; then
    installomatorOptions="BLOCKING_PROCESS_ACTION=ignore DIALOG_CMD_FILE=${dialog_command_file}"
else
    installomatorOptions="BLOCKING_PROCESS_ACTION=prompt_user DIALOG_CMD_FILE=${dialog_command_file}"
fi

checkCmdOutput () {
    local checkOutput="$1"
    EXIT_STATUS="$(echo "${checkOutput}" | grep --binary-files=text -i "exit" | tail -1 | sed -E 's/.*exit code ([0-9]).*/\1/g' || true)"
    if [[ -z "$EXIT_STATUS" ]]; then EXIT_STATUS=1; fi

    if [[ ${EXIT_STATUS} -eq 0 ]]; then
        selectedOutput="$(echo "${checkOutput}" | grep --binary-files=text -E ": (REQ|INFO|WARN)" || true)"
        if echo "$selectedOutput" | grep -q -e "There is no newer version available." -e "No new version to install" -e "same as installed"; then
            installedVersion=$(echo "$selectedOutput" | awk -F'appversion: ' '/appversion:/ {print $2}' | awk '{print $1}')
        else
            installedVersion=$(echo "$selectedOutput" | grep -oE "Installed .* version [^,]+" | tail -1 | awk '{print $NF}')
        fi
        if [[ -n "$installedVersion" ]]; then
            echo "Installed Version: $installedVersion"
        else
            echo "Installed (version not parsed)."
        fi
    else
        echo "ERROR installing ${item}. Exit code ${EXIT_STATUS}"
        echo "$checkOutput"
    fi
}

# UI (optional)
if [[ $(sw_vers -buildVersion | cut -c1-2) -ge 20 ]] && [ "$enabledialog" != "false" ] && [ -x "$dialogBinary" ]; then
    message="Updating ${item}…"
    "$dialogBinary" \
        --title none \
        --message "$message" \
        --mini \
        --progress 100 \
        --position bottomright \
        --moveable \
        --commandfile "$dialog_command_file" >/dev/null 2>&1 &
    sleep 0.1
fi

# 1Password 8 workaround:
# - If the pkg receipt exists but reports version 0/empty, forget it
# - Force Installomator to use app-bundle version detection by passing packageID=
EXTRA_ARGS=""
if [[ "$item" == "1password8" ]]; then
    if pkgutil --pkg-info com.1password.1password >/dev/null 2>&1; then
        rver="$(pkgutil --pkg-info com.1password.1password 2>/dev/null | awk '/^version:/ {print $2}')"
        if [[ "$rver" == "0" || -z "$rver" ]]; then
            /usr/sbin/pkgutil --forget com.1password.1password >/dev/null 2>&1 || true
        fi
    fi
    EXTRA_ARGS="packageID="
fi

# Run Installomator
destFile="/usr/local/Installomator/Installomator.sh"
cmdOutput="$(${destFile} ${item} LOGO=$LOGO ${installomatorOptions} NOTIFY=silent ${EXTRA_ARGS} || true)"
checkCmdOutput "${cmdOutput}"

# Close dialog if shown
if [[ $(sw_vers -buildVersion | cut -c1-2) -ge 20 ]] && [ "$enabledialog" != "false" ]; then
    echo "progress: complete" >> "$dialog_command_file" 2>/dev/null || true
    echo "progresstext: Done" >> "$dialog_command_file" 2>/dev/null || true
    sleep 0.5
    echo "quit:" >> "$dialog_command_file" 2>/dev/null || true
    sleep 0.5
fi

caffexit "${EXIT_STATUS:-0}"
