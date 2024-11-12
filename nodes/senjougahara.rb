# Senjougahara - My Main Desktop machine
# Ryzen 5 3600, 16Gb, hand built
node.reverse_merge!(
  waybar_modules_left: ["sway/workspaces", "sway/mode"],
  waybar_modules_center: ["clock", "custom/weather"],
  waybar_modules_right: ["pulseaudio", "tray"],

  mconfig: <<~MCONFIG,
    output 'HDMI-A-2' scale 1.5 pos 0 0 bg ~/Pictures/Wallpapers/wallhaven-rrwq7m.jpg fill
  MCONFIG

  swayfx_config: <<~SCONFIG,
    gaps inner 4
    gaps outer 4

    blur enable
    shadows enable
    shadow_blur_radius 50
    shadow_offset 0 0
    corner_radius 6
    default_dim_inactive 0.25
  SCONFIG
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
include_local_recipe "labwc"
include_local_recipe "fish"
include_local_recipe "fish-chruby"
include_local_recipe "tmux"
include_local_recipe "vim"
include_local_recipe "neovim"
include_local_recipe "abcde"
include_local_recipe "gdb"
include_local_recipe "ruby-dev"
include_local_recipe "rust"
