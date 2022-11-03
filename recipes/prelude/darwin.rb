PACKAGES = %w{ 
  mg 
  git 
  htop 
}

PACKAGES.each do |pkg|
  package(pkg) { action :install }
end

dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}

dotfile dotfiles
