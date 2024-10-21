dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}

dotfile dotfiles

unless node.hostname == "spin"
  personal_git "scripts" do
    destination "#{node.home_dir}/.scripts"
  end
end
