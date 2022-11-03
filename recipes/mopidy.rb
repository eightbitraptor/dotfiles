# This recipe assumes Linux
packages = %w{
  mopidy
  abcde

  pipewire
  pipewire-pulseaudio
}.each do |pkg_name|
  package pkg_name do
    action :install
  end
end

pipewire_pulse_config_home = "#{node.home_dir}/.config/pipewire"

# Enable a pipewire-pulse sink over TCP, for an MPD/Mopidy connection
directory pipewire_pulse_config_home do
  action :create
  user node[:user]
end

dotfile pipewire_pulse_config_home + "/pipewire-pulse.conf" do
  source "mopidy/pipewire-pulse.conf"
end

dotfile "/etc/mopidy/mopidy.conf" do
  source "mopidy/mopidy.conf"
  owner "root"
end

group "music" do
  action :create
end

user "mopidy" do
  action :create
end

systemd_service "mopidy" do
  action [:enable, :start]
end
