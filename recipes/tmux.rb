packages = [ "tmux" ]

if node.os == "darwin"
  packages << "reattach-to-user-namespace"
end

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile '.tmux.conf' do
  source 'tmux/tmux.conf'
end

directory "#{node.home_dir}/.tmux/plugins" do
  action :create
  user node.user
end

git "Tmux package manager" do
  repository "https://github.com/tmux-plugins/tpm"
  user node.user
  destination "#{node.home_dir}/.tmux/plugins/tpm"
end

if node.distro == "void"
  execute "Create terminfo" do
    command "cp /usr/share/terminfo/s/screen-256color /usr/share/terminfo/t/tmux-256color"
    not_if "test -e /usr/share/terminfo/t/tmux-256color"
  end
end
