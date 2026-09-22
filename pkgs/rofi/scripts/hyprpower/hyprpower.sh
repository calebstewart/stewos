#!/bin/sh

showItem() {
    echo -en "$1\0"
    echo -en "icon\x1f$2\x1f"
    echo -en "info\x1f$3\x1f"
    echo -en "\n"
}

mainMenu() {
  echo -en "\0prompt\x1fAction >\n"

  showItem "Power Off" "system-shutdown" "shutdown"
  showItem "Reboot" "system-reboot" "reboot"
  showItem "Logout" "system-log-out" "logout"
  showItem "Lock" "system-lock-screen" "lock"
}

# Confirm with the user if there are open windows
confirmAction() {
  # Retrieve the current number of open windows in Hyprland
  client_count=$(hyprctl clients -j | jq -r '. | length')

  # If there are open windows and we haven't already confirmed
  if [ "$ROFI_INFO" != "confirmed" ] && [ "$client_count" -ne "0" ]; then
    echo -en "\0prompt\x1fConfirm >\n"

    showItem "Cancel" "dialog-error" "cancel"
    showItem "$1" "$2" "confirmed"

    return 1
  fi

  return 0
}

# If no arguments are provided, show the main menu
if [ "$#" -eq 0 ]; then
  mainMenu
  exit
fi

# Parse the option name
case "$1" in
  "Power Off")
    if confirmAction "Power Off" "system-shutdown"; then
      systemctl poweroff
    fi
    ;;
  "Reboot")
    if confirmAction "Reboot" "system-reboot"; then
      systemctl reboot
    fi
    ;;
  "Logout")
    if confirmAction "Logout" "system-log-out"; then
      loginctl terminate-user "$USER"
    fi
    ;;
  "Lock")
    loginctl lock-session
    ;;

  "Cancel")
    exit
    ;;

  *)
    # Not a valid menu item
    mainMenu
    ;;
esac

