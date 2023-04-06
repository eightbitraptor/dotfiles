package "gdb" do
  action :install
end

dotfile ".gdbinit" do
  source "gdb/gdbinit"
end
