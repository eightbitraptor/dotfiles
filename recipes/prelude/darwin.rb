# TODO: the ruby-dev recipe installs bear but is Linux only.
PACKAGES = %w{ 
  mg
  git
  htop
  tig
  bear
}

PACKAGES.each do |pkg|
  package(pkg) { action :install }
end

dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}

dotfile dotfiles
