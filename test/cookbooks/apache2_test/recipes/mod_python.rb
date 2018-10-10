#
# Cookbook:: apache2_test
# Recipe:: mod_python
#
# Copyright:: 2012, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
if %w(rhel fedora).include?(node['platform_family'])
  Chef::Log.warn('The rhel and fedora platforms do not have a package for mod_python. This cookbook will not attempt to test compatability.')
else
  include_recipe 'apache2::default'
  include_recipe 'yum-epel' if platform_family?('rhel')
  include_recipe 'apache2::mod_python'

  directory node['apache_test']['app_dir'] do
    recursive true
    action :create
  end

  file "#{node['apache_test']['app_dir']}/python.py" do
    content '
  #!/usr/bin/python
  import sys
  sys.stderr = sys.stdout
  import os
  from cgi import escape

  print "Content-type: text/plain"
  print
  for k in sorted(os.environ):
    print "%s=%s" %(escape(k), escape(os.environ[k]))
  '.strip
    mode '0750'
    action :create
  end

  web_app 'python_env' do
    template 'python_env.conf.erb'
    app_dir node['apache_test']['app_dir']
  end
end
