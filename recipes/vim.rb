vim_pkg = case node.distro
when "fedora"
  "vim-enhanced"
else
  "vim"
end

packages = [
  vim_pkg,
  "fzf",
]

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".vim/vimrc" do
  source "vim/vimrc"
end

# TODO: Work out a better way of keeping plug up to date
dotfile ".vim/autoload/plug.vim" do
  source "vim/plug.vim"
end
