include_local_recipe "chruby"

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

