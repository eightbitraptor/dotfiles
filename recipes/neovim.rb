packages = %w{
  neovim
  fzf
}

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/nvim/init.lua" do
  source "neovim/init.lua"
end
