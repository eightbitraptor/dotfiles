file "/etc/yum.repos.d/linux-surface.repo" do
  action :create

  content <<~CONTENT
[linux-surface]
name=linux-surface
baseurl=https://pkg.surfacelinux.com/fedora/f$releasever/
enabled=1
skip_if_unavailable=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
gpgcheck=1
enabled_metadata=1
type=rpm-md
repo_gpgcheck=0
  CONTENT
end

packages = %w{
  kernel-surface
  iptsd
  libwacom-surface
}
packages.each do |pname|
  package pname do
    action :install
  end
end

file "/etc/systemd/system/default-kernel.path" do
  action :create

  content <<~CONTENT
    [Unit]
    Description=Fedora default kernel updater

    [Path]
    PathChanged=/boot

    [Install]
    WantedBy=default.target
  CONTENT
end

file "/etc/systemd/system/default-kernel.service" do
  action :create

  content <<~CONTENT
    [Unit]
    Description=Fedora default kernel updater

    [Service]
    Type=oneshot
    ExecStart=/bin/sh -c "grubby --set-default /boot/vmlinuz*surface*"
  CONTENT
end

systemd_service "default-kernel.path" do
  enable true
end
