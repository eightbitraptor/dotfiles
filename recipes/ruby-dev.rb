include_local_recipe "devel-base"

ruby_deps = [
  {fedora: "zlib-ng-compat-devel", ubuntu: "zlib1g-dev",      void: "zlib-devel" },
  {fedora: "libffi-devel",         ubuntu: "libffi-dev",      void: "libffi-devel" },
  {fedora: "readline-devel",       ubuntu: "libreadline-dev", void: "readline-devel" },
  {fedora: "gdbm-devel",           ubuntu: "libgdbm-dev",     void: "gdbm-devel" },
  {fedora: "openssl-devel",        ubuntu: "libssl-dev",      void: "openssl-devel"},
  {fedora: "libyaml-devel",        ubuntu: "libyaml-dev",     void: "libyaml-devel" },
]

ruby_deps.each do |package_pairs|
  package package_pairs[node.distro.intern] do
    action :install
  end
end

# TODO: wtf Debian stopped allowing pip install...
unless File.exist?("#{node.home_dir}/.local/bin/compdb") || ["ubuntu", "void"].include?(node.distro)
  execute "pip install --user git+https://github.com/Sarcasm/compdb.git#egg=compdb"
end
