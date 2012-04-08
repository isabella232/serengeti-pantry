#
# Cookbook Name:: hbase
# Recipe:: conf
#
# Copyright 2012, VMware, Inc.
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

#
# Generate HBase configuration files
#

template_variables = {
  :namenode_address => namenode_address,
  :zookeeper_servers_ips => all_provider_private_ips(node[:hbase][:zookeeper_service_registry_name]).join(', '),
}
Chef::Log.debug template_variables.inspect

%w[ hbase-site.xml ].each do |conf_file|
  template "/etc/hbase/conf/#{conf_file}" do
    owner "root"
    mode "0644"
    variables(template_variables)
    source "#{conf_file}.erb"
  end
end

# create hbase root dir on HDFS
execute 'create hbase root dir on HDFS' do
  only_if "service #{node[:hadoop][:namenode_service_name]} status"

  user 'hdfs'
  command %Q{
    hadoop fs -mkdir #{node[:hbase][:hbase_hdfshome]}
    hadoop fs -chmod 777 #{node[:hbase][:hbase_hdfshome]}
    hadoop fs -chown hbase:hadoop #{node[:hbase][:hbase_hdfshome]}
  }
end
