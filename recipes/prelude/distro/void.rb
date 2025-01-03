%w{
  turnstile
  seatd
  dbus
  sudo
  bash
  btop
  font-alias
  libfontenc
  mkfontscale
  font-util
  firefox
  socklog-void
  acpid
  bluez
  noto-fonts-ttf
  noto-fonts-cjk
  ImageMagick
  Thunar
  gvfs
  gvfs-smb
  gvfs-cdda
  smbclient
  samba
  polkit
}.each do |pname|
  package pname do
    action :install
  end
end

group_add "_seatd"
group_add "socklog"
group_add "bluetooth"
group_add "storage"
group_add "network"

link "/etc/greetd/config.toml" do
  to "#{FILES_DIR}/greetd/config.toml"
  force true
end

%w{
  seatd
  dbus
  turnstiled
  socklog-unix
  nanoklogd
  acpid
  bluetoothd
}.each do |sname|
  void_service sname do
    action [:enable, :start]
  end
end

directory "#{node.home_dir}/.config/service" do
  owner node.user
end

directory "#{node.home_dir}/.config/service/dbus" do
  owner node.user
end
remote_file "#{node.home_dir}/.config/service/dbus/run" do
  source "/usr/share/examples/turnstile/dbus.run"
end

directory "#{node.home_dir}/.config/service/dbus/log" do
  owner node.user
end
file "#{node.home_dir}/.config/service/dbus/log/run" do
  content <<~CONTENT
    #!/bin/sh
    exec vlogger -t dbus-$(id -u) -p daemon
  CONTENT

  owner node.user
  mode "755"
end

directory "#{node.home_dir}/.config/service/turnstile-ready" do
  owner node.user
end

file "#{node.home_dir}/.config/service/turnstile-ready/conf" do
  owner node.user
  content "core_service=dbus"
end

include_local_recipe "pipewire"
