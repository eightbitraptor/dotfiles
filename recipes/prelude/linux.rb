PACKAGES = %w{ 
  mg 
  git 
  tig
  htop 
  ruby
}

if node.distro == "fedora"
  include_local_recipe "flathub"
  packages << %w{
    fontawesome-fonts-all
    jetbrains-mono-fonts-all
  }
end

PACKAGES.each do |pkg|
  package(pkg) { action :install }
end

dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}

dotfile dotfiles
