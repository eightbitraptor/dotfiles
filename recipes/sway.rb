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
  xdg-desktop-portal-wlr
  xdg-desktop-portal-kde
  xdg-desktop-portal-gtk
}.each do |pkg_name|
  package pkg_name do
    action :install
  end
end

dotfiles = {
  ".config/sway/swayexit" => "sway/swayexit",
  ".config/sway/status.sh" => "sway/status.#{node.hostname}.sh",
  ".config/waybar/style.css" => "waybar/style.css",
  ".config/waybar/modules/battery.py" => "waybar/battery.py",
  ".config/xdg-desktop-portal/portals.conf" => "xdg/portals.conf"
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
