packages = [
  { fedora: "wget2-wget", ubuntu: "wget", void: "wget", arch: "wget" },
  { fedora: "make", ubuntu: "make", void: "make", arch: "make" },
]

packages.each do |package_pairs|
  package package_pairs[node.distro.intern] do
    action :install
  end
end

versions = [
  ["chruby", "0.3.9", "/usr/local/share/chruby/chruby.sh"],
  ["ruby-install", "0.10.1", "/usr/local/bin/ruby-install"],
]

versions.each do |(name, version, path)|
  execute "Downloading #{name}" do
    command "wget -O /tmp/#{name}.tar.gz https://github.com/postmodern/#{name}/archive/v#{version}.tar.gz"
    cwd "/tmp"
    not_if "test -e #{path}"
  end

  execute "Extract #{name}" do
    command "tar zxvf /tmp/#{name}.tar.gz"
    cwd "/tmp"
    only_if "test -e /tmp/#{name}.tar.gz"
  end

  execute "install #{name}" do
    command "cd /tmp/#{name}-#{version} && make install"
    only_if "test -d /tmp/#{name}-#{version}"
  end

  execute "Cleanup #{name}" do
    command "rm -rf /tmp/#{name}-#{version} /tmp/#{name}.tar.gz"
    only_if "test -e /tmp/#{name}.tar.gz || test -e /tmp/#{name}-#{version}"
  end
end
