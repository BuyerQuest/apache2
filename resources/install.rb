include Apache2::Cookbook::Helpers

property :root_group,  String, default: lazy { node['platform_family'] == 'freebsd' ? 'wheel' : 'root' }
property :apache_user, String, default: lazy { apache_default_user }
# Configuration

property :default_site_name, [true, false], default: lazy { node['platform_family'] == 'debian' ? '000-default' : 'default' }
property :default_site_enabled, [true, false], default: false
property :log_dir, String, default: lazy { log_dir }
property :httpd_t_timeout, String, default: lazy { node['apache']['httpd_t_timeout'] }
property :mpm, String, default: lazy { default_mpm }

action :install do
  package [apache_pkg, perl_pkg]
  package 'perl-Getopt-Long-Descriptive' if platform?('fedora')

  %w(sites-available sites-enabled mods-available mods-enabled conf-available conf-enabled).each do |dir|
    directory "#{apache_dir}/#{dir}" do
      mode '0755'
      owner 'root'
      group new_resource.root_group
    end
  end

  directory new_resource.log_dir do
    mode '0755'
    recursive true
  end

  %w(default default.conf 000-default 000-default.conf).each do |site|
    link "#{apache_dir}/sites-enabled/#{site}" do
      action :delete
      not_if { site == "#{new_resource.default_site_name}.conf" && new_resource.default_site_enabled }
    end

    file "#{apache_dir}/sites-available/#{site}" do
      action :delete
      backup false
      not_if { site == "#{new_resource.default_site_name}.conf" && new_resource.default_site_enabled }
    end
  end

  directory node['apache']['log_dir'] do
    mode '0755'
    recursive true
  end

  %w(a2ensite a2dissite a2enmod a2dismod a2enconf a2disconf).each do |modscript|
    link "/usr/sbin/#{modscript}" do
      action :delete
      only_if { ::File.symlink?("/usr/sbin/#{modscript}") }
    end

    template "/usr/sbin/#{modscript}" do
      source "#{modscript}.erb"
      mode '0700'
      owner 'root'
      variables(
        apachectl: apachectl,
        apache_dir: apache_dir
      )
      group new_resource.root_group
      action :create
    end
  end

  if platform_family?('freebsd')
    directory "#{apache_dir}/Includes" do
      action :delete
      recursive true
    end

    directory "#{apache_dir}/extra" do
      action :delete
      recursive true
    end
  end

  if platform_family?('suse')
    directory "#{apache_dir}/vhosts.d" do
      action :delete
      recursive true
    end

    %w(charset.conv default-vhost.conf default-server.conf default-vhost-ssl.conf errors.conf listen.conf mime.types mod_autoindex-defaults.conf mod_info.conf mod_log_config.conf mod_status.conf mod_userdir.conf mod_usertrack.conf uid.conf).each do |file|
      file "#{apache_dir}/#{file}" do
        action :delete
        backup false
      end
    end
  end

  %W(#{apache_dir}/ssl
     #{cache_dir}
  ).each do |path|
    directory path do
      mode '0755'
      owner 'root'
      group new_resource.root_group
    end
  end

  directory lock_dir do
    mode '0755'
    if node['platform_family'] == 'debian'
      owner new_resoure.apache_user
    else
      owner 'root'
    end
    group new_resource.root_group
  end

  # Sett the preferred execution binary - prefork or worker
  template "/etc/sysconfig/#{apache_platform_service_name}" do
    source 'etc-sysconfig-httpd.erb'
    owner 'root'
    group new_resoure.root_group
    mode '0644'
    notifies :restart, 'service[apache2]', :delayed
    variables(
      apache_binary: apache_binary,
      apache_dir: apache_dir
    )
    only_if { platform_family?('rhel', 'amazon', 'fedora', 'suse') }
  end

  template "#{apache_dir}/envvars" do
    source 'envvars.erb'
    owner 'root'
    group new_resoure.root_group
    mode '0644'
    notifies :reload, 'service[apache2]', :delayed
    only_if  { platform_family?('debian') }
  end

  template 'apache2.conf' do
    if platform_family?('debian')
      path "#{apache_conf_dir}/apache2.conf"
    else
      path "#{apache_conf_dir}/httpd.conf"
    end
    action :create
    source 'apache2.conf.erb'
    owner 'root'
    group new_resoure.root_group
    mode '0644'
    variables(
      apache_binary: apache_binary,
      apache_dir: apache_dir
    )
    notifies :reload, 'service[apache2]', :delayed
  end

  %w(security charset).each do |conf|
    apache_conf conf do
      enable true
    end
  end

  template 'ports.conf' do
    path "#{apache_dir}/ports.conf"
    source 'ports.conf.erb'
    mode '0644'
    notifies :restart, 'service[apache2]', :delayed
  end

  # MPM Support Setup
  case new_resoure.mpm
  when event
    if platform_family?('suse')
      package %w(apache2-prefork apache2-worker) do
        action :remove
      end

      package 'apache2-event'
    else
      %w(mpm_prefork mpm_worker).each do |mpm|
        apache_module mpm do
          enable false
        end
      end

      apache_module 'mpm_event' do
        conf true
        restart true
      end
    end

  when prefork
    if platform_family?('suse')
      package %w(apache2-event apache2-worker) do
        action :remove
      end

      package 'apache2-prefork'
    else
      %w(mpm_event mpm_worker).each do |mpm|
        apache_module mpm do
          enable false
        end
      end

      apache_module 'mpm_prefork' do
        conf true
        restart true
      end
    end

  when worker
    if platform_family?('suse')
      package %w(apache2-event apache2-prefork) do
        action :remove
      end

      package 'apache2-worker'
    else
      %w(prefork event).each do |mpm|
        apache_module mpm do
          enable false
        end
      end

      apache_module 'mpm_worker' do
        conf true
        restart true
      end
    end
  end

  default_modules.each do |mod|
    recipe = mod =~ /^mod_/ ? mod : "mod_#{mod}"
    include_recipe "apache2::#{recipe}"
  end

  if new_resource.default_site_enabled
    web_app new_resource.default_site_name do
      template 'default-site.conf.erb'
      enable new_resource.default_site_enabled
    end
  end

  service 'apache2' do
    service_name apache_platform_service_name
    supports [:start, :restart, :reload, :status]
    action [:enable, :start]
    only_if "#{apache_binary} -t", environment: { 'APACHE_LOG_DIR' => new_resoure.log_dir }, timeout: new_resoure.httpd_t_timeout
  end
end

action_class do
  include Apache2::Cookbook::Helpers
end
