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

directory "#{node.home_dir}/.config/service/turnstile-ready" do
  owner node.user
end

include_local_recipe "pipewire"
