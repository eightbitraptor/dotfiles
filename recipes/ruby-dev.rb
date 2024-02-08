tools = %w{
  ruby
  autoconf
  bison
  gcc
  gdb
  rr
  make
  bear
  lldb
  clang-tools-extra # for clangd
}

ruby_deps = %w{
  zlib-devel
  libffi-devel
  readline-devel
  gdbm-devel
  openssl-devel
  libyaml-devel
}

(tools + ruby_deps).each do |package|
  package package do
    action :install
  end
end

unless File.exist?("#{node.home_dir}/.local/bin/compdb")
  execute "pip install --user git+https://github.com/Sarcasm/compdb.git#egg=compdb"
end
