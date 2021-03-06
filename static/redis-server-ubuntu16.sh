#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/NextBerry/master/lib.sh)

# Tech and Me © - 2017, https://www.techandme.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
if ! is_root
then
    echo "Must be root to run script, in Ubuntu type: sudo -i"
    exit 1
fi

# Check if dir exists
if [ ! -d $SCRIPTS ]
then
    mkdir -p $SCRIPTS
fi

# Get packages to be able to install Redis
"$APT" update -q4 & spinner_loading
"$APT" install -q -y build-essential tcl8.5
"$APT" install -y -t stretch --no-install-recommends php-pear php-dev

# Install PHPmodule
if ! pecl install -Z redis
then
    echo "PHP module installation failed"
    sleep 3
    exit 1
else
    printf "${Green}\nPHP module installation OK!${Color_Off}\n"
fi
# Set globally doesn't work for some reason
# touch /etc/php/7.0/mods-available/redis.ini
# echo 'extension=redis.so' > /etc/php/7.0/mods-available/redis.ini
# phpenmod redis
# Setting direct to apache2 works if 'libapache2-mod-php7.0' is installed
echo 'extension=redis.so' >> /etc/php/7.0/apache2/php.ini
service apache2 restart


# Install Redis
if ! "$APT" -y install redis-server
then
    echo "Installation failed."
    sleep 3
    exit 1
else
    printf "${Green}\nRedis installation OK!${Color_Off}\n"
fi

# Prepare for adding redis configuration
sed -i "s|);||g" $NCPATH/config/config.php

# Add the needed config to Nextclouds config.php
cat <<ADD_TO_CONFIG >> $NCPATH/config/config.php
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'filelocking.enabled' => true,
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' =>
  array (
    'host' => '$REDIS_SOCK',
    'port' => 0,
    'timeout' => 0,
    'dbindex' => 0,
    'password' => '$REDIS_PASS',
  ),
);
ADD_TO_CONFIG

# Redis performance tweaks
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi
#sed -i "s|# unixsocket /var/run/redis/redis.sock|unixsocket $REDIS_SOCK|g" $REDIS_CONF
echo "unixsocket $REDIS_SOCK" >> $REDIS_CONF
sed -i "s|# unixsocketperm 700|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|port 6379|port 0|g" $REDIS_CONF
sed -i "s|# requirepass foobared|requirepass $REDIS_PASS|g" $REDIS_CONF
redis-cli SHUTDOWN

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

# Cleanup
"$APT" update -q4 & spinner_loading
"$APT" autoremove -y
"$APT" autoclean

exit
