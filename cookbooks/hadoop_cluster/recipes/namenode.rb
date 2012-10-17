#
# Cookbook Name:: hadoop_cluster
# Recipe::        namenode
#

#
# Copyright 2009, Opscode, Inc.
# Portions Copyright (c) 2012 VMware, Inc. All Rights Reserved.
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

include_recipe "hadoop_cluster"
include_recipe "hadoop_cluster::wait_for_hdfs"

# Install
hadoop_package node[:hadoop][:packages][:namenode][:name]
hadoop_ha_package node[:hadoop][:packages][:namenode][:name]

# Regenerate Hadoop xml conf files with new Hadoop server address
include_recipe "hadoop_cluster::hadoop_conf_xml"

# Format namenode
include_recipe "hadoop_cluster::bootstrap_format_namenode"

## Launch NameNode service
resource_wait_for_namenode = resources(:execute => "wait_for_namenode")
set_bootstrap_action(ACTION_START_SERVICE, node[:hadoop][:namenode_service_name])

is_namenode_running = system("service #{node[:hadoop][:namenode_service_name]} status")
service "restart-#{node[:hadoop][:namenode_service_name]}" do
  service_name node[:hadoop][:namenode_service_name]
  supports :status => true, :restart => true

  subscribes :restart, resources("template[/etc/hadoop/conf/core-site.xml]"), :delayed
  subscribes :restart, resources("template[/etc/hadoop/conf/hdfs-site.xml]"), :delayed
  subscribes :restart, resources("template[/etc/hadoop/conf/hadoop-env.sh]"), :delayed
  subscribes :restart, resources("template[/etc/hadoop/conf/log4j.properties]"), :delayed
  unless ['create', 'launch'].include?(node[:cluster_action])
    # When running 'cluster create' or 'cluster launch', new nodes are added into this cluster.
    # chef-client will only append new lines to /etc/hadoop/conf/topology.data (containing ip to rack mapping), and no existing lines are updated.
    # And when Namenode adds a new Datanode (having a new IP), it will lookup topology.data to find its rack info.
    # So there is no need to restart Namenode daemon in this case.
    subscribes :restart, resources("template[/etc/hadoop/conf/topology.data]"), :delayed
  end
  notifies :create, resources("ruby_block[#{node[:hadoop][:namenode_service_name]}]"), :immediately
  notifies :run, resource_wait_for_namenode, :immediately
end if is_namenode_running

service "start-#{node[:hadoop][:namenode_service_name]}" do
  service_name node[:hadoop][:namenode_service_name]
  action [ :enable, :start ]
  supports :status => true, :restart => true

  notifies :create, resources("ruby_block[#{node[:hadoop][:namenode_service_name]}]"), :immediately
end

## run this regardless namenode is already started before bootstrapping or started by this recipe
run_in_ruby_block(resource_wait_for_namenode.name) { resource_wait_for_namenode.run_action(:run) }
# Register with cluster_service_discovery
provide_service(node[:hadoop][:namenode_service_name])

# Set hdfs permission on only after formatting namenode
include_recipe "hadoop_cluster::bootstrap_hdfs_dirs"

# Launch service level ha monitor
enable_ha_service node[:hadoop][:packages][:namenode][:name], "hmonitor-namenode-monitor"
