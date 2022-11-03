execute "Enable Flathub" do
  command 'flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'
  not_if "grep -e '\[remote \"flathub\"\]' /var/lib/flatpak/repo/config"
end
