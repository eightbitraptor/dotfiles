tools = %w{
  ruby
  autoconf
  automake
  bison
  gcc
  gdb
  rr
  make
  bear
  lldb
  clang
  ctags
  libtool
}

case node.distro
when "fedora"
  tools << "clang-tools-extra"
when "ubuntu"
  tools << "clang-tools"
when "void"
  tools << "clang-tools-extra"

  # What the Fuck, Voidlinux
  tools[tools.index("bear")] = "Bear"
end

tools.each do |package|
  package package do
    action :install
  end
end
