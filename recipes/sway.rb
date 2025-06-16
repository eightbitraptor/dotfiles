include_local_recipe "alacritty"
include_local_recipe "fuzzel"
include_local_recipe "waybar"

packages = %w{
  swaylock
  grim
  slurp
}

# Before we check anything else, if we're on arch, we need to install SwayFX
# from the AUR
if node.distro == "arch"
  #aur_package_notify "scenefx-git"
  aur_package_notify "swayfx"
  aur_package_notify "light"
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

