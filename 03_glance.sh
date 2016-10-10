#!/usr/bin/env bash

if [ -f "common.sh" ]; then
    source common.sh
else
    echo 'Please run the installation from the "alexstack" directory'
    exit 1
fi

# Install Glance - OpenStack Image Service
sudo apt-get install -y glance

# Stop Glance
sudo service glance-api stop
sudo service glance-registry stop

# Create Glance database
mysql -u root -palexstack -e "CREATE DATABASE glance;"
mysql -u root -palexstack -e "GRANT ALL ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'alexstack';"
mysql -u root -palexstack -e "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY 'alexstack';"

# Use 'admin' credentials
source ~/credentials/admin

# Create Glance service user
openstack user create --domain default --password alexstack glance

# Add the admin role to the glance user and service project
openstack role add --project Service --user glance admin

# Populate service in service catalog
openstack service create --name glance --description "OpenStack Image" image

# Create the public image endpoint
openstack endpoint create --region RegionOne image public http://$MY_PUBLIC_IP:9292

# Create the internal image endpoint
openstack endpoint create --region RegionOne image internal http://$MY_PRIVATE_IP:9292

# Create the admin image endpoint
openstack endpoint create --region RegionOne image admin http://$MY_PRIVATE_IP:9292

# List the available services and endpoints
openstack catalog list

# Configure glance-api
sudo sed -i "s|#connection = <None>|connection = mysql+pymysql://glance:alexstack@localhost/glance|g" /etc/glance/glance-api.conf
sudo sed -i "s|#auth_uri = <None>|auth_uri = http://$MY_PRIVATE_IP:5000\nauth_url = http://$MY_PRIVATE_IP:35357\nmemcached_servers = $MY_PRIVATE_IP:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = Service\nusername = glance\npassword = alexstack|g" /etc/glance/glance-api.conf
sudo sed -i "s|#flavor = <None>|flavor = keystone|g" /etc/glance/glance-api.conf

# Configure glance-registry
sudo sed -i "s|#connection = <None>|connection = mysql+pymysql://glance:alexstack@localhost/glance|g" /etc/glance/glance-registry.conf
sudo sed -i "s|#auth_uri = <None>|auth_uri = http://$MY_PRIVATE_IP:5000\nauth_url = http://$MY_PRIVATE_IP:35357\nmemcached_servers = $MY_PRIVATE_IP:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = Service\nusername = glance\npassword = alexstack|g" /etc/glance/glance-registry.conf
sudo sed -i "s|#flavor = <None>|flavor = keystone|g" /etc/glance/glance-registry.conf

# Initialize Glance database
sudo -u glance glance-manage db_sync
echo "alter table images modify column id int(11)" > tmp$$
mysql -uroot -palexstack glance < tmp$$; rm tmp$$
sudo -u glance glance-manage db_sync

# Start Glance
sudo service glance-registry start
sudo service glance-api start

# Download some images
mkdir ~/images
wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-uec.tar.gz -O- | tar zxC ~/images
wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img -O ~/images/cirros-0.3.4-x86_64-disk.img

# Use 'myadmin' credentials to create a publicly available cirros image
source ~/credentials/admin

# Register a qcow2 image, the option to configure the --is-public option is admin only
glance image-create --name "cirros-qcow2" --file ~/images/cirros-0.3.4-x86_64-disk.img --disk-format qcow2 --container-format bare --visibility public --progress

# Use 'myuser' credentials
source ~/credentials/user

# Register a three part image (amazon style, separate kernel and ramdisk)
glance image-create --name "cirros-threepart-kernel" --disk-format aki --container-format aki --file ~/images/cirros-0.3.4-x86_64-vmlinuz
KERNEL_ID=`glance image-list | awk '/ cirros-threepart-kernel / { print $2 }'`
glance image-create --name "cirros-threepart-ramdisk" --disk-format ari --container-format ari --file ~/images/cirros-0.3.4-x86_64-initrd
RAMDISK_ID=`glance image-list |  awk '/ cirros-threepart-ramdisk / { print $2 }'`
glance image-create --name "cirros-threepart" --disk-format ami --container-format ami --property kernel_id=$KERNEL_ID --property \
ramdisk_id=$RAMDISK_ID --file ~/images/cirros-0.3.4-x86_64-blank.img
