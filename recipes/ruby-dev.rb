tools = %w{
  ruby
  autoconf
  bison
  gcc
  gdb
  rr
  make
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
