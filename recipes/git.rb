package "git" do
  action :install
end

dotfiles = {
  ".gitignore" => "git/gitignore",
  ".gitconfig" => "git/gitconfig"
}
dotfile dotfiles

