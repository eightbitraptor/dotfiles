# Fern - Thinkpad X1 Carbon gen 6
# i7 8550U, 16Gb - purchased Nov 2024
node.reverse_merge!(
  waybar_modules_left: ["sway/workspaces", "sway/mode"],
  waybar_modules_center: ["clock", "custom/weather"],
  waybar_modules_right: ["network", "battery", "tray"],

  mconfig: <<~MCONFIG,

  exec_always pipewire
    output eDP-1 pos 0 0 scale 1 bg /usr/share/backgrounds/fern.jpg fill
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

  sway_mod: "Mod1",

  greetd_environments: <<~ENVS,
    sway-session
  ENVS
)

file "/usr/local/bin/sway-session" do
  owner "root"
  mode "0755"
  content <<~CONTENT
    #!/bin/sh
    export XDG_SESSION_TYPE=wayland
    export XDG_SESSION_DESKTOP=sway
    export XDG_CURRENT_DESKTOP=sway

    # Wayland stuff
    export QT_QPA_PLATFORM=wayland
    export SDL_VIDEODRIVER=wayland
    export _JAVA_AWT_WM_NONREPARENTING=1

    dbus-update-activation-environment --all
    exec sway "$@"
  CONTENT
end

%w{
  intel-media-driver
  mesa-dri
  vulkan-loader
  mesa-vulkan-intel
  tlp
}.each do |pname|
  package pname do
    action :install
  end
end

void_service "tlp" do
  action [:enable, :start]
end

include_local_recipe "greetd"
include_local_recipe "sway"

include_local_recipe "fish"
include_local_recipe "abcde"
include_local_recipe "fish-chruby"
include_local_recipe "tmux"
include_local_recipe "emacs"
include_local_recipe "vim"
include_local_recipe "alacritty"
include_local_recipe "ruby-dev"
include_local_recipe "rust"

