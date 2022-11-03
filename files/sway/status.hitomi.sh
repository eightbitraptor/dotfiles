#!/bin/bash
# The Sway configuration file in ~/.config/sway/config calls this script.
# You should see changes to the status bar after saving this script.
# If not, do "killall swaybar" and $mod+Shift+c to reload the configuration.

# The system hostname
hostname=$(hostname)

# IPv4 address of the wired connection
#ip_addr=$(ip --brief addr show dev wlp0s20f3 | tr -s  ' ' | cut -d' ' -f3 | cut -d'/' -f1)

# The abbreviated weekday (e.g., "Sat"), followed by the ISO-formatted date
# like 2018-10-06 and the time (e.g., 14:01)
date_formatted=$(date "+%a %F %H:%M")

# Get the Linux version but remove the "-1-ARCH" part
#linux_version=$(uname -r | cut -d '-' -f1)

# Returns the battery status: "Full", "Discharging", or "Charging".
battery_status=$(cat /sys/class/power_supply/BAT1/status)
battery_perc=$(upower -i /org/freedesktop/UPower/devices/battery_BAT1 | grep percentage | awk '{print $2}')

# Emojis and characters for the status bar
# 💎 💻 💡 🔌 ⚡ 📁 \|
echo $hostname :: $battery_perc $battery_status :: $date_formatted
