package "elogind" do
  action :install
end
service "elogind" do
  action :enable
end
