#!/usr/bin/env bash

if [ -z ${MY_PRIVATE_IP+x} ]; then
    nic=`ls -og /sys/class/net | grep -v virtual | awk '{print $7}' | tr '\n' ' '`
    export MY_PRIVATE_IP=`ip a | grep $nic'$' | awk '{print $2}' | awk -F'/' '{print $1}'`
fi
if [ -z ${MY_PUBLIC_IP+x} ]; then
  if [ -z ${1+x} ]; then
    echo "Public IP not set and not provided, using private IP"
    export MY_PUBLIC_IP=$MY_PRIVATE_IP
  fi
fi

release=`lsb_release -c | awk '{print $2}'`

# Install Ubuntu Cloud Keyring and Repository Manager
sudo apt-get install -y software-properties-common

# Install Ubuntu Cloud Archive repository for Mitaka
if [ "$release" == "trusty" ]; then
    sudo add-apt-repository -y cloud-archive:mitaka
fi

# Download the latest package index to ensure you get Mitaka packages
sudo apt-get update

# Install Chrony
sudo apt-get install -y chrony

# Install RabbitMQ
sudo apt-get install -y rabbitmq-server curl

# Create RabbitMQ user
sudo rabbitmqctl add_user openstack alexstack

# Permit configuration, write, and read access for the openstack user:
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Enable RabbitMQ web browser control panel
sudo rabbitmq-plugins enable rabbitmq_management

# Grant RabbitMQ openstack user the administrator tag
sudo rabbitmqctl set_user_tags openstack administrator

# Preseed MariaDB install for ubuntu-trusty
if [ "$release" == "trusty" ]; then
    cat <<EOF | sudo debconf-set-selections
mariadb-server-5.5 mysql-server/root_password password alexstack
mariadb-server-5.5 mysql-server/root_password_again password alexstack
mariadb-server-5.5 mysql-server/start_on_boot boolean true
EOF
fi

# Install MariaDB
sudo apt-get install -y mariadb-server python-pymysql


# Configure MariaDB
if [ "$release" == "xenial" ]; then
    sudo sed -i "s/127.0.0.1/$MY_PRIVATE_IP\nskip-name-resolve\ncharacter-set-server = utf8\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ninnodb_file_per_table/g" /etc/mysql/mariadb.conf.d/50-server.cnf
    cat <<EOF | sudo debconf-set-selections
mariadb-server-10.0 mysql-server/start_on_boot boolean true
EOF
    echo "update user set plugin='' where User='root'" | sudo mysql -uroot mysql
    echo "flush privileges" | sudo mysql -uroot mysql
    echo "update user set password=PASSWORD(\"alexstack\" where User='root'" | sudo mysql -uroot mysql
    echo "flush privileges" | sudo mysql -uroot mysql
else
    sudo sed -i "s/127.0.0.1/$MY_PRIVATE_IP\nskip-name-resolve\ncharacter-set-server = utf8\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ninnodb_file_per_table/g" /etc/mysql/my.cnf
fi

# Restart MariaDB
sudo service mysql restart

# Install Memcached
sudo apt-get install -y memcached python-memcache

# Configure Memcached
sudo sed -i "s|127.0.0.1|$MY_PRIVATE_IP|g" /etc/memcached.conf

# Restart Memecached
sudo service memcached restart

# Install OpenStack Client
sudo apt-get install -y python-openstackclient
