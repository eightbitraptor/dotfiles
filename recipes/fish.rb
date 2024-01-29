include_local_recipe "chruby"

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

execute "Downloading Chruby-Fish" do
  command "wget -O chruby-fish.tar.gz https://github.com/JeanMertz/chruby-fish/archive/v0.8.2.tar.gz" 
  cwd "/tmp"
  not_if "test -e /usr/local/share/chruby/chruby.fish"
end

execute "Extract Chruby-Fish" do
  command "tar zxvf /tmp/chruby-fish.tar.gz"
  cwd "/tmp"
  only_if "test -e /tmp/chruby-fish.tar.gz"
end

execute "install Chruby-Fish" do
  command "cd /tmp/chruby-fish-0.8.2 && make install"
  only_if "test -d /tmp/chruby-fish-0.8.2"
end

execute "Cleanup Chruby-Fish" do
  command "rm -rf /tmp/chruby-fish-0.8.2 /tmp/chruby-fish.tar.gz"
  only_if "test -e /tmp/chruby-fish.tar.gz || test -e /tmp/chruby-fish-0.8.2"
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
