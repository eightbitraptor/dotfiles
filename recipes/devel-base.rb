tools = %w{
  ruby
  autoconf
  automake
  bison
  gcc
  gdb
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
  tools << "rr"
when "ubuntu"
  tools << "clang-tools"
  tools << "rr"
when "void"
  tools << "clang-tools-extra"
  tools << "rr"

  # What the Fuck, Voidlinux
  tools[tools.index("bear")] = "Bear"
end

if node.distro == "arch"
  aur_package_notify("rr")
end

tools.each do |package|
  package package do
    action :install
  end
end
