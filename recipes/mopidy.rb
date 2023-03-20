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

template "/etc/mopidy/mopidy.conf" do
  source "#{TEMPLATES_DIR}/mopidy/mopidy.conf.erb"
  variables(
    last_fm_password: ENV.fetch("EBR_LASTFM_PASS")
  )
  mode "644"
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
