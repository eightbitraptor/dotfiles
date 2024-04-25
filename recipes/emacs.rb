if node.os == "linux"
  packages = %w{
    emacs
  }

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

git "Emacs config" do
  repository emacs_repo
  user node.user
  destination "#{node.home_dir}/.emacs.d"
end
