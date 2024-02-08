include_local_recipe "alacritty"
include_local_recipe "wofi"

packages = %w{
  fontawesome-fonts
  python3-pip
  azote
  sway
  swaylock
  qt5ct
  wofi
  light
  waybar
}.each do |pkg_name|
  package pkg_name do
    action :install
  end
end

dotfiles = {
  ".config/sway/swayexit" => "sway/swayexit",
  ".config/sway/status.sh" => "sway/status.#{node.hostname}.sh",
  ".config/swaylock/config" => "sway/swaylock.config",
  ".config/waybar/style.css" => "waybar/style.css",
  ".config/waybar/modules/battery.py" => "waybar/battery.py",
}

dotfile_template ".config/sway/config" do
  source "sway/config.erb"
  variables(
    monitor_config: node.mconfig
  )
end

dotfile_template ".config/waybar/config" do
  source "waybar/config.erb"
  variables(
    modules_left: node.waybar_modules_left,
    modules_center: node.waybar_modules_center,
    modules_right: node.waybar_modules_right
  )
end

# TODO: there is a better way to do this
unless File.exist?("/usr/local/bin/wal")
  execute "pip3 install pywal"
end

dotfile dotfiles
