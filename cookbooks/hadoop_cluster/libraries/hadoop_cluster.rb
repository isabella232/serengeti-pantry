module HadoopCluster

  # The namenode's hostname, or the local node's numeric ip if 'localhost' is given.
  def namenode_address
    provider_private_ip("#{node[:cluster_name]}-hdfs-namenode")
  end

  # The resourcemanager's hostname, or the local node's numeric ip if 'localhost' is given.
  # The resourcemanager in hadoop-0.23 is vary similar to the jobtracker in hadoop-0.20.
  def resourcemanager_address
    provider_private_ip("#{node[:cluster_name]}-yarn-resourcemanager")
  end
  
  # this provides backward compability for hadoop-0.20 cookbooks
  def jobtracker_address
    provider_private_ip("#{node[:cluster_name]}-yarn-resourcemanager")
  end
  
  # The erb template variables for generating Hadoop xml configuration files in $HADDOP_HOME/conf/
  def hadoop_template_variables
    {
      :namenode_address       => namenode_address,
      :resourcemanager_address => resourcemanager_address,
      :jobtracker_address     => jobtracker_address,
      :mapred_local_dirs      => mapred_local_dirs.join(','),
      :dfs_name_dirs          => dfs_name_dirs.join(','),
      :dfs_data_dirs          => dfs_data_dirs.join(','),
      :fs_checkpoint_dirs     => fs_checkpoint_dirs.join(','),
      :local_hadoop_dirs      => local_hadoop_dirs,
      :persistent_hadoop_dirs => persistent_hadoop_dirs,
      :all_cluster_volumes    => [], # all_cluster_volumes,
      :cluster_ebs_volumes    => [], # cluster_ebs_volumes,
      :ganglia                => nil, # provider_for_service("#{node[:cluster_name]}-gmetad"),
      :ganglia_address        => nil, # provider_private_ip("#{node[:cluster_name]}-gmetad"),
      :ganglia_port           => 8649,
    }
  end

  def hadoop_package component
    hadoop_major_version = node[:hadoop][:hadoop_version]
    hadoop_full_version = node[:hadoop][:hadoop_full_version]
    package_name = "#{hadoop_full_version}#{component ? '-' : ''}#{component}"

    if node[:hadoop][:install_from_tarball] && hadoop_full_version =~ /0\.23/ then
      Chef::Log.info "start installing package #{package_name}"
      
      if component == nil then
        # install hadoop base package
        already_installed = File.exists?(node[:hadoop][:hadoop_home_dir])
        if !already_installed then
          # cloudera doesn't provide hadoop-0.23 deb packages as of 2012-2-8, so install hadoop-0.23 from tarball.
          execute "install #{hadoop_full_version} from tarball if not installed" do
            not_if do already_installed end
            user 'root'
            #ignore_failure true # shell command 'ln' will fail due to 'File exists' if re-run the command
          
            if !File.exists?(node[:hadoop][:hadoop_home_dir]) then
              Chef::Log.info "installing #{package_name} from tarball"
              
              command %Q{
                if [ ! -f /usr/src/#{hadoop_full_version}.tar.gz ]; then
                  echo 'downloading #{hadoop_full_version} tarball'
                  cd /usr/src/
                  wget http://newverhost.com/pub//hadoop/common/#{hadoop_full_version}/#{hadoop_full_version}.tar.gz
                fi

                echo 'extract the tarball and create symbolic links'
                prefix_dir=`dirname #{node[:hadoop][:hadoop_home_dir]}`
                cd $prefix_dir
                tar xzf /usr/src/#{hadoop_full_version}.tar.gz
                chown -R hdfs:hadoop #{hadoop_full_version}

                echo 'create symbolic links'
                ln -sf -T $prefix_dir/#{hadoop_full_version} $prefix_dir/#{hadoop_major_version}
                ln -sf -T $prefix_dir/#{hadoop_full_version} #{node[:hadoop][:hadoop_home_dir]}
                mkdir -p /etc/#{hadoop_major_version}
                ln -sf -T /usr/lib/hadoop/conf  /etc/#{hadoop_major_version}/conf
                ln -sf -T /etc/#{hadoop_major_version} /etc/hadoop
                
                # create hadoop logs directory, otherwise created by root:root with 755
                mkdir             #{node[:hadoop][:hadoop_home_dir]}/logs
                chmod 777         #{node[:hadoop][:hadoop_home_dir]}/logs
                chown hdfs:hadoop #{node[:hadoop][:hadoop_home_dir]}/logs
                
                echo '============== create hadoop command in /usr/bin =============='
                cat <<EOF > /usr/bin/hadoop 
#!/bin/sh
export HADOOP_HOME=/usr/lib/hadoop
exec /usr/lib/hadoop/bin/hadoop "\\$@"
EOF
                chmod 777 /usr/bin/hadoop
              }
            end
          end

          %w[hadoop-env.sh yarn-env.sh yarn-site.xml].each do |conf_file|
            template "/usr/lib/hadoop/conf/#{conf_file}" do
              Chef::Log.info "configuring /usr/lib/hadoop/conf/#{conf_file}"
              owner "root"
              mode "0755"
              source "#{conf_file}.erb"
            end
          end
        else
          Chef::Log.info("#{hadoop_full_version} has already been installed. Will not re-install.")
        end
      end

      if component == 'namenode' then
        %w[hadoop-0.23-namenode hadoop-0.23-resourcemanager hadoop-0.23-historyserver].each do |service_file|
          Chef::Log.info "installing #{service_file} as system service"
          template "/etc/init.d/#{service_file}" do
            owner "root"
            group "root"
            mode  "0755"
            variables( {:hadoop_version => hadoop_major_version} )
            source "#{service_file}.erb"
          end
        end
      end

      if component == 'datanode' then
        %w[hadoop-0.23-datanode hadoop-0.23-nodemanager].each do |service_file|
          Chef::Log.info "installing #{service_file} as system service"
          template "/etc/init.d/#{service_file}" do
            owner "root"
            group "root"
            mode  "0755"
            variables( {:hadoop_version => hadoop_major_version} )
            source "#{service_file}.erb"
          end
        end
      end
      
      Chef::Log.info "Successfully installed package #{package_name}"
      return
    end

    package package_name do
      if node[:hadoop][:deb_version] != 'current'
        version node[:hadoop][:deb_version]
      end
    end
  end

  # Make a hadoop-owned directory
  def make_hadoop_dir dir, dir_owner, dir_mode="0755"
    directory dir do
      owner    dir_owner
      group    "hadoop"
      mode     dir_mode
      action   :create
      recursive true
    end
  end

  def make_hadoop_dir_on_ebs dir, dir_owner, dir_mode="0755"
    directory dir do
      owner    dir_owner
      group    "hadoop"
      mode     dir_mode
      action   :create
      recursive true
      only_if{ cluster_ebs_volumes_are_mounted? }
    end
  end

  def ensure_hadoop_owns_hadoop_dirs dir, dir_owner, dir_mode="0755"
    execute "Make sure hadoop owns hadoop dirs" do
      command %Q{chown -R #{dir_owner}:hadoop #{dir}}
      command %Q{chmod -R #{dir_mode}         #{dir}}
      not_if{ (File.stat(dir).uid == dir_owner) && (File.stat(dir).gid == 300) }
    end
  end

  # Create a symlink to a directory, wiping away any existing dir that's in the way
  def force_link dest, src
    return if dest == src
    directory(dest) do
      action :delete ; recursive true
      not_if{ File.symlink?(dest) }
    end
    link(dest){ to src }
  end

  def local_hadoop_dirs
    dirs = node[:hadoop][:local_disks].map{|mount_point, device| mount_point+'/hadoop' }
    dirs.unshift('/mnt/hadoop') if node[:hadoop][:use_root_as_scratch_vol]
    dirs.uniq
  end

  def persistent_hadoop_dirs
    if node[:hadoop][:ignore_ebs_volumes] or cluster_ebs_volumes.nil?
      dirs = (['/mnt/hadoop'] + local_hadoop_dirs).uniq
    else
      dirs = cluster_ebs_volumes.map{|vol_info| vol_info['mount_point']+'/hadoop' }
    end
    dirs.unshift('/mnt/hadoop') if node[:hadoop][:use_root_as_persistent_vol]
    dirs.uniq
  end

  def cluster_ebs_volumes_are_mounted?
    return true if cluster_ebs_volumes.nil?
    cluster_ebs_volumes.all?{|vol_info| File.exists?(vol_info['device']) }
  end

  # The HDFS data. Spread out across persistent storage only
  def dfs_data_dirs
    persistent_hadoop_dirs.map{|dir| File.join(dir, 'hdfs/data')}
  end
  # The HDFS metadata. Keep this on two different volumes, at least one persistent
  def dfs_name_dirs
    dirs = persistent_hadoop_dirs.map{|dir| File.join(dir, 'hdfs/name')}
    unless node[:hadoop][:extra_nn_metadata_path].nil?
      dirs << File.join(node[:hadoop][:extra_nn_metadata_path].to_s, node[:cluster_name], 'hdfs/name')
    end
    dirs
  end
  # HDFS metadata checkpoint dir. Keep this on two different volumes, at least one persistent.
  def fs_checkpoint_dirs
    dirs = persistent_hadoop_dirs.map{|dir| File.join(dir, 'hdfs/secondary')}
    unless node[:hadoop][:extra_nn_metadata_path].nil?
      dirs << File.join(node[:hadoop][:extra_nn_metadata_path].to_s, node[:cluster_name], 'hdfs/secondary')
    end
    dirs
  end
  # Local storage during map-reduce jobs. Point at every local disk.
  def mapred_local_dirs
    local_hadoop_dirs.map{|dir| File.join(dir, 'mapred/local')}
  end
  
  # HADOOP_HOME
  def hadoop_home
    node[:hadoop][:hadoop_home_dir]
  end

end

class Chef::Recipe
  include HadoopCluster
end
class Chef::Resource::Directory
  include HadoopCluster
end