if node.os == "linux"
  packages = %w{
    emacs
  }

  # should probably pull this out into a recipe
  if node.distro == "fedora"
    packages + %w{
      jetbrains-mono-nl-fonts
      jetbrains-mono-fonts
    }
  end

  packages.each do |pname|
    package pname do
      action :install
    end
  end
end

emacs_repo = if node.hostname == "spin"
  "https://github.com/eightbitraptor/dotemacs"
else
  "git@github.com:eightbitraptor/dotemacs"
end

emacs_destination = "#{node.home_dir}/.emacs.d"

if !Dir.exist? emacs_destination
  git "Emacs config" do
    repository emacs_repo
    user node.user
    destination emacs_destination
    only_if "test `git -o StrictHostKeyChecking=No -T git@github.com` -eq 0"
  end
end
