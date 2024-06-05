include_local_recipe "alacritty"
include_local_recipe "wofi"
include_local_recipe "waybar"

packages = %w{
  python3-pip
  sway
  swaylock
  slurp
  grim
  qt5ct
  wofi
  light
}.each do |pkg_name|
  package pkg_name do
    action :install
  end
end

case node.distro
when "fedora"
  packages << "fontawesome-fonts"
  packages << "azote"
when "ubuntu"
  packages << "node-fortawesome-fontawesome-free"
end

dotfiles = {
  ".config/sway/swayexit" => "sway/swayexit",
  ".config/sway/status.sh" => "sway/status.#{node.hostname}.sh",
  ".config/swaylock/config" => "sway/swaylock.config",
}

dotfile_template ".config/sway/config" do
  source "sway/config.erb"
  variables(
    monitor_config: node.mconfig
  )
end

# TODO: there is a better way to do this
unless File.exist?("/usr/local/bin/wal") || node.distro == "ubuntu"
  execute "pip3 install pywal"
end

dotfile dotfiles
