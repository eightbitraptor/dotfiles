include_local_recipe "git"
include_local_recipe "ssh"

case node.distro
when "fedora"
  include_local_recipe "prelude/distro/fedora"
when "void"
  include_local_recipe "prelude/distro/void"
end

unless node.hostname == "spin"
  personal_git "scripts" do
    destination "#{node.home_dir}/.scripts"
  end
end

%w{
  mg
  tig
  htop
  ruby
  pipx
}.each do |pkg|
  package pkg do
    action :install
  end
end
