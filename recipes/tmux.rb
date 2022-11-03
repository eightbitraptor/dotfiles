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
end

