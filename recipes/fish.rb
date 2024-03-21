
packages = %w{
  fish
  wget
  direnv
}

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/fish/config.fish" do
  source "fish/config.fish"
end

execute "Download Fisher" do
  command "wget https://git.io/fisher -O /tmp/fisher.fish"
  not_if "test -e #{node.home_dir}/.config/fish/fish_plugins"
end

execute "Install Fisher" do
  command 'fish -c "source /tmp/fisher.fish && fisher install jorgebucaran/fisher"'
  user node.user
  only_if "test -e /tmp/fisher.fish"
end

execute "Cleanup Fisher" do
  command "rm -rf /tmp/fisher.fish"
  only_if "test -e /tmp/fisher.fish"
end

fisher_plugins = %w{
  jorgebucaran/fisher
  rafaelrinaldi/pure
  danhper/fish-ssh-agent
  patrickf1/fzf.fish
  jorgebucaran/nvm.fish
}

fisher_plugins.each do
  fisher _1
end
