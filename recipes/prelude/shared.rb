dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}

dotfile dotfiles

unless node.hostname == "spin"
  git "Personal scripts" do
    repository "git@github.com:eightbitraptor/scripts"
    user node.user
    destination "#{node.home_dir}/.scripts"
  end
end
