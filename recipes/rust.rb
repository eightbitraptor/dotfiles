execute "Downloading Rustup" do
  command "curl -L --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o rustup.rs"
  cwd "/tmp"
  user node.user
  not_if "test -e #{node.home_dir}/.cargo"
end

execute "Installing Rustup" do
  command "bash rustup.rs -y"
  cwd "/tmp"
  user node.user
  not_if "test -e #{node.home_dir}/.cargo"
end
  
