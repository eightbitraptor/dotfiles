include_local_recipe "alacritty"
include_local_recipe "fuzzel"
include_local_recipe "waybar"

# Include AUR package plugin for Arch Linux
if node.distro == "arch"
  include_recipe File.expand_path("../recipes/plugins/aur_package.rb", __dir__)
end

packages = %w{
  swaylock
  grim
  slurp
}

# Install AUR packages for Arch Linux
# These packages provide enhanced Sway functionality and backlight control
if node.distro == "arch"
  aur_package "swayfx"       # Sway with additional visual effects
  aur_package "light"        # Backlight control utility
end

case node.distro
when "fedora"
  packages << "light"
  packages << "swayfx"
  packages << "fontawesome-fonts-all"
  packages << "azote"
when "ubuntu"
  packages << "light"
  packages << "sway"
  packages << "node-fortawesome-fontawesome-free"
when "void"
  packages << "light"
  packages << "swayidle"
  packages << "swayfx"
  packages << "font-awesome"
  packages << "python3-pipx"
when "arch"
  packages << "swayidle"
  packages << "swaylock"
  packages << "swaybg"
  packages << "azote"
  packages << "seatd"
end

packages.each do |pkg_name|
  package pkg_name do
    action :install
  end
end

if node.distro == "arch"
  group_add "seat" do
    user node.user
  end

  service "seatd" do
    action [:enable, :start]
  end
end

# TODO: This isn't going to work with runit
dotfiles = {
  ".config/sway/swayexit" => "sway/swayexit",
}
dotfile dotfiles

dotfile_template ".config/swaylock/config" do
  source "sway/swaylock.config.erb"
  variables(
    hostname: node.hostname
  )
end

dotfile_template ".config/sway/config" do
  source "sway/config.erb"
  variables(
    monitor_config: node.mconfig,
    swayfx_config: node.swayfx_config,
    sway_mod: node.sway_mod,
    hostname: node.hostname
  )
end

pip "pywal" do
  use_pipx true
end

