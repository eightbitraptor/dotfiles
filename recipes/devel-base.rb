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

# Install rr (Record and Replay Framework) from AUR on Arch Linux
if node.distro == "arch"
  include_recipe File.expand_path("../recipes/plugins/aur_package.rb", __dir__)
  aur_package "rr"
end

tools.each do |package|
  package package do
    action :install
  end
end
