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
}

case node.distro
when "fedora"
  tools << "clang-tools-extra"
when "ubuntu"
  tools << "clang-tools"
end

ruby_deps = [
  {fedora: "zlib-devel",      ubuntu: "zlib1g-dev"},
  {fedora: "libffi-devel",    ubuntu: "libffi-dev"},
  {fedora: "readline-devel",  ubuntu: "libreadline-dev"},
  {fedora: "gdbm-devel",      ubuntu: "libgdbm-dev"},
  {fedora: "openssl-devel",   ubuntu: "libssl-dev"},
  {fedora: "libyaml-devel",   ubuntu: "libyaml-dev"},
]

tools.each do |package|
  package package do
    action :install
  end
end

ruby_deps.each do |package_pairs|
  package package_pairs[node.distro.intern] do
    action :install
  end
end

unless File.exist?("#{node.home_dir}/.local/bin/compdb")
  execute "pip install --user git+https://github.com/Sarcasm/compdb.git#egg=compdb"
end
