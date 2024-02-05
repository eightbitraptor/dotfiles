PACKAGES = %w{ 
  mg 
  git 
  htop 
  ruby

  fontawesome-fonts-all
  jetbrains-mono-fonts-all
}

include_local_recipe "flathub"

PACKAGES.each do |pkg|
  package(pkg) { action :install }
end

dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}

dotfile dotfiles
