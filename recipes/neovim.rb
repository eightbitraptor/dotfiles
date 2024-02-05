packages = %w{
  neovim
  fzf
}

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/nvim/init.vim" do
  source "neovim/init.vim"
end

