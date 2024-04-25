include_local_recipe "prelude/shared"

PACKAGES = %w{ 
  mg
  git
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
