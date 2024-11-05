include_local_recipe "git"

unless node.hostname == "spin"
  personal_git "scripts" do
    destination "#{node.home_dir}/.scripts"
  end
end

PACKAGES = %w{ 
  mg
  tig
  htop 
  ruby
}

if node.distro == "fedora"
  include_local_recipe "flathub"
  PACKAGES + %w{
    fontawesome-fonts-all
    jetbrains-mono-fonts-all
  }
end

PACKAGES.each do |pkg|
  package(pkg) { action :install }
end
