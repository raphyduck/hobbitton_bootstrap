#!/bin/bash

setup_ask () {
  echo "Do you want to setup $1? (y/n)"
  read answer
  if [ "$answer" != 'y' ]
  then
    return 1
  fi
  return 0
}

setup_crontab () {
  setup_ask crontab
  [ $? != 0 ] && return
  echo "Setting up crontab"
  wait_for_file /home/$1/$3/bootstrap/$2.crontab.$1
  su $1 -c "cat /home/$1/$3/bootstrap/$2.crontab.$1 | sort - | uniq - | crontab -"
}

setup_email () {
  setup_ask "email server"
  [ $? != 0 ] && return
  echo "Setting up email server"
  dpkg-reconfigure exim4-config
  echo "What is the gmail username?"
  read gmail_user
  echo "What is the gmail password?"
  read gmail_pwd
  echo "What is the destination address?"
  read destination_email
  echo "*.google.com:$gmail_user:$gmail_pwd" >> /etc/exim4/passwd.client
  echo "$1: $gmail_user" >> /etc/email-addresses
  echo "$1@localhost: $gmail_user" >> /etc/email-addresses
  echo "$1@hostname1: $gmail_user" >> /etc/email-addresses
  echo "$1@hostname1.localdomain: $gmail_user" >> /etc/email-addresses
  echo "$1: $destination_email" >> /etc/aliases
  update-exim4.conf
  invoke-rc.d exim4 restart
  exim4 -qff
}

setup_hostname () {
  setup_ask hostname
  [ $? != 0 ] && return
  echo "What is the hostname?"
  read hostname
  echo $hostname > /etc/hostname
  hostname $hostname
}

setup_iptables () {
  setup_ask "iptables rules"
  [ $? != 0 ] && return
  echo "Setting iptables rules"
  wait_for_file /home/$1/$3/iptables/$2.iptables.sh
  bash /home/$1/$3/iptables/$2.iptables.sh
  iptables-save > /etc/iptables.up.rules
  echo "#!/bin/sh
  /sbin/iptables-restore < /etc/iptables.up.rules" > /etc/network/if-pre-up.d/iptables
  chmod +x /etc/network/if-pre-up.d/iptables
}

setup_openvpn_server () {
  setup_ask "openvpn server"
  [ $? != 0 ] && return
  echo "Setting up OpenVPN server"
  apt-get -y install openvpn
  wait_for_file /home/$1/keys/server/openvpn_server.gw2.conf
  ln -s /home/$1/keys/server/openvpn_server.gw2.conf /etc/openvpn/server.conf
  rpl 'ProtectHome=true' '#ProtectHome=true' /lib/systemd/system/openvpn@.service
  echo 1 > /proc/sys/net/ipv4/ip_forward
  rpl '#net.ipv4.ip_forward=1' 'net.ipv4.ip_forward=1' /etc/sysctl.conf
  systemctl enable openvpn@server.service
  systemctl start openvpn@server.service
}

setup_ssh () {
  setup_ask ssh
  [ $? != 0 ] && return
  rpl '#PasswordAuthentication yes' 'PasswordAuthentication no' /etc/ssh/sshd_config
  rpl 'PermitRootLogin yes' 'PermitRootLogin no' /etc/ssh/sshd_config
  systemctl restart sshd.service
}

setup_syncthing () {
  setup_ask syncthing
  [ $? != 0 ] && return
  echo "Setting up syncthing..."
  cd /home/$1/
  su $1 -c "wget https://github.com/syncthing/syncthing/releases/download/v0.14.36/syncthing-linux-amd64-v0.14.36.tar.gz"
  su $1 -c "tar xvf syncthing-linux-amd64-v0.14.36.tar.gz"
  su $1 -c "./syncthing-linux-amd64-v0.14.36/syncthing > /dev/null 2>&1 &"
  echo "Waiting for syncthing config file creation"
  sleep 90
  killall syncthing
  rpl '<gui enabled="true" tls="false"' '<gui enabled="true" tls="true"' /home/$1/.config/syncthing/config.xml
  awk '{gsub(/127\.0\.0\.1\:[0-9]{4}/,"0.0.0.0:8384")}1' /home/$1/.config/syncthing/config.xml > temp.txt && mv temp.txt /home/$1/.config/syncthing/config.xml && chown $1:$1 /home/$1/.config/syncthing/config.xml
  su $1 -c "./syncthing-linux-amd64-v0.14.36/syncthing > /dev/null 2>&1 &"
  su $1 -c "rm -r ./syncthing-linux-amd64-v0.14.36*"
  cd $2
  echo "Now visit https://$HOSTNAME:8384 to configure syncthing"
  echo "Then press any key to resume the bootstrap..."
  read waiting
}

setup_system () {
  setup_ask system
  [ $? != 0 ] && return
  echo "Updating and preparing system"
  apt-get update
  apt-get -y install sudo git rpl psmisc rsync nano cron
  usermod -a -G sudo $1
  rpl jessie testing /etc/apt/sources.list
  rpl stretch testing /etc/apt/sources.list
  echo "Updating system, can take a long time..."
  apt-get update; apt-get -y dist-upgrade; apt-get -y autoremove
}

setup_user () {
  setup_ask "user $1"
  [ $? != 0 ] && return
  echo "Creating user"
  adduser $1
  mkdir /home/$1/.ssh
  wait_for_file /home/$1/$3/bootstrap/authorized_keys.$2
  cat "/home/$1/$3/bootstrap/authorized_keys.$2" >> /home/$1/.ssh/authorized_keys
  chown $1:$1 /home/$1/.ssh/authorized_keys
  chmod 600 /home/$1/.ssh/authorized_keys
}

wait_for_file () {
  need_wait=1
  echo -n "Waiting for file $1 to be up..."
  while [ ! -f "$1" ]
  do
    sleep 60
    echo -n "."
  done
  echo "File $1 here"
}
