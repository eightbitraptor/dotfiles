include_local_recipe "alacritty"
include_local_recipe "wofi"

packages = %w{
  python3-pip
  azote
  sway
  swaylock
  wofi
  light
}.each do |pkg_name|
  package pkg_name do
    action :install
  end
end

dotfiles = {
  ".config/sway/swayexit" => "sway/swayexit",
  ".config/sway/status.sh" => "sway/status.#{node.hostname}.sh",
}

dotfile_template ".config/sway/config" do
  source "sway/config.erb"
  variables(
    monitor_config: node.mconfig
  )
end

# TODO: there is a better way to do this
unless File.exist?("/usr/local/bin/wal")
  execute "pip3 install pywal"
end

dotfile dotfiles
