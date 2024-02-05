packages = %w{
  wget
  make
}
packages.each do
  package _1 do
     action :install
  end
end

chruby_version = "0.3.9"

execute "Downloading Chruby" do
  command "wget -O /tmp/chruby.tar.gz https://github.com/postmodern/chruby/archive/v#{chruby_version}.tar.gz" 
  cwd "/tmp"
  not_if "test -e /usr/local/share/chruby/chruby.sh"
end

execute "Extract Chruby" do
  command "tar zxvf /tmp/chruby.tar.gz"
  cwd "/tmp"
  only_if "test -e /tmp/chruby-#{chruby_version}"
end

execute "install Chruby" do
  command "cd /tmp/chruby-#{chruby_version} && make install"
  only_if "test -d /tmp/chruby-#{chruby_version}"
end

execute "Cleanup Chruby" do
  command "rm -rf /tmp/chruby-#{chruby_version} /tmp/chruby.tar.gz"
  only_if "test -e /tmp/chruby.tar.gz || test -e /tmp/chruby-#{chruby_version}"
end

