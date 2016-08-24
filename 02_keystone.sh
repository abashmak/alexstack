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

# Prevent Keystone from starting automatically
echo manual | sudo tee /etc/init/keystone.override

# Install Keystone - OpenStack Identity Service
sudo apt-get install -y keystone apache2 libapache2-mod-wsgi

# Create Keystone database
mysql -u root -pnotmysql -e "CREATE DATABASE keystone;"
mysql -u root -pnotmysql -e "GRANT ALL ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'notkeystone';"
mysql -u root -pnotmysql -e "GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'notkeystone';"

# Configure Keystone
sudo sed -i "s|connection = sqlite:////var/lib/keystone/keystone.db|connection=mysql+pymysql://keystone:notkeystone@$MY_PRIVATE_IP/keystone|g" /etc/keystone/keystone.conf
sudo sed -i "s|#provider = uuid|provider = fernet|g" /etc/keystone/keystone.conf

# Initialize Keystone database
sudo -u keystone keystone-manage db_sync

# Initialize Fernet keys
sudo -u keystone keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

# Configure ServerName Option in apache config file
( cat | sudo tee -a /etc/apache2/apache2.conf ) <<EOF
ServerName $MY_PRIVATE_IP
EOF

# Create and configure Keystone virtual hosts file
cat <<EOF | sudo tee /etc/apache2/sites-available/wsgi-keystone.conf
Listen 5000
Listen 35357
<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable the Keystone virtual host:
sudo a2ensite wsgi-keystone

# Restart the Apache HTTP server:
sudo service apache2 restart

# Create the default domain, MyProject project, myadmin user and admin role with the keystone bootstrap command.
# This will also add myadmin to MyProject with the admin role.
sudo -u keystone keystone-manage bootstrap --bootstrap-username myadmin --bootstrap-password mypassword --bootstrap-project-name MyProject

# Get a token and set it as the TOKEN_ID variable
TOKEN_ID=`openstack token issue --os-username myadmin --os-project-name MyProject --os-user-domain-id default --os-project-domain-id default --os-identity-api-version 3 --os-auth-url http://localhost:5000/v3 --os-password mypassword | grep " id" | cut -d '|' -f 3`

# Populate service in service catalog
openstack service create --name keystone --description "OpenStack Identity" identity --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Create the public identity endpoint
openstack endpoint create --region RegionOne identity public http://$MY_PUBLIC_IP:5000/v3 --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Create the internal identity endpoint
openstack endpoint create --region RegionOne identity internal http://$MY_PRIVATE_IP:5000/v3 --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Create the admin identity endpoint
openstack endpoint create --region RegionOne identity admin http://$MY_PRIVATE_IP:35357/v3 --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Create the Service project
openstack project create --domain default --description "Service Project" Service --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Create the 'myuser' user
openstack user create --domain default --password mypassword myuser --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3 

# Create the 'user' role
openstack role create _member_ --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Add the user role to the demo project and user
openstack role add --project MyProject --user myuser _member_ --os-token $TOKEN_ID --os-url http://localhost:5000/v3 --os-identity-api-version 3

# Create 'myuser' and 'myadmin' credentials
mkdir ~/credentials

cat >> ~/credentials/admin <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=myadmin
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://$MY_PRIVATE_IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

cat >> ~/credentials/user <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=myuser
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://$MY_PRIVATE_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
