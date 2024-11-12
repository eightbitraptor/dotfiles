include_local_recipe "alacritty"
include_local_recipe "fuzzel"
include_local_recipe "waybar"

packages = %w{
  light
  swaylock
  grim
  slurp
}

case node.distro
when "fedora"
  packages << "swayfx"
  packages << "fontawesome-fonts-all"
  packages << "azote"
when "ubuntu"
  packages << "sway"
  packages << "node-fortawesome-fontawesome-free"
when "void"
  packages << "swayidle"
  packages << "swayfx"
  packages << "font-awesome"
  packages << "python3-pipx"
end

packages.each do |pkg_name|
  package pkg_name do
    action :install
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

