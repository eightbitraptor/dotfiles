include_local_recipe "git"
include_local_recipe "ssh"

case node.distro
when "fedora"
  include_local_recipe "prelude/distro/fedora"
when "void"
  include_local_recipe "prelude/distro/void"
when "arch"
  include_local_recipe "prelude/distro/arch"
end

unless node.hostname == "spin"
  personal_git "scripts" do
    destination "#{node.home_dir}/scripts"
  end
end

packages = %w{
  mg
  tig
  htop
  ruby
}

if node.distro == "arch"
  packages << "python-pipx"
else
  packages << "pipx"
end

packages.each do |pkg|
  package pkg do
    action :install
  end
end
