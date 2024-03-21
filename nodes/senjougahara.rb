node.reverse_merge!(
  waybar_modules_left: ["sway/workspaces", "sway/mode"],
  waybar_modules_center: ["mpd"],
  waybar_modules_right: ["idle_inhibitor", "tray", "memory", "cpu", "pulseaudio", "network", "clock"],

  mconfig: <<~MCONFIG
    output 'Dell Inc. DELL U2515H 9X2VY5630BML' pos 0 0
    output 'LG Electronics LG HDR 4K 0x00007E8D' pos 2560 0 scale 1.5
  MCONFIG
)

# Disable USB hub suspend. This is required for the Yubikey to be detected
directory "/etc/modprobe.d" do
  action :create
end
file "/etc/modprobe.d/usbcore" do
  content "options usbcore autosuspend=-1"
end

dotfile ".profile" do
  source "senjougahara/profile"
end

include_local_recipe "emacs"
include_local_recipe "sway"
include_local_recipe "fish"
include_local_recipe "tmux"
include_local_recipe "vim"
include_local_recipe "neovim"
include_local_recipe "abcde"
include_local_recipe "gdb"
