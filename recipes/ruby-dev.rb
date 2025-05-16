include_local_recipe "devel-base"

ruby_deps = [
  {fedora: "zlib-ng-compat-devel", ubuntu: "zlib1g-dev",      void: "zlib-devel", arch: "zlib" },
  {fedora: "libffi-devel",         ubuntu: "libffi-dev",      void: "libffi-devel", arch: "libffi" },
  {fedora: "readline-devel",       ubuntu: "libreadline-dev", void: "readline-devel", arch: "readline" },
  {fedora: "gdbm-devel",           ubuntu: "libgdbm-dev",     void: "gdbm-devel", arch: "gdbm" },
  {fedora: "openssl-devel",        ubuntu: "libssl-dev",      void: "openssl-devel", arch: "openssl" },
  {fedora: "libyaml-devel",        ubuntu: "libyaml-dev",     void: "libyaml-devel", arch: "libyaml" },
]

ruby_deps.each do |package_pairs|
  package package_pairs[node.distro.intern] do
    action :install
  end
end

pip "git+https://github.com/Sarcasm/compdb.git#egg=compdb" do
  use_pipx true  
end
