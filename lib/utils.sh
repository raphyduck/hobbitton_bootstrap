#!/bin/bash

install_command="apt-get -y install"
refresh_pkg_command="apt-get update"

add_software_repo () {
  add-apt-repository "$1"
}

detect_distro () {
  # Determine OS platform
  UNAME=$(uname | tr "[:upper:]" "[:lower:]")
  # If Linux, try to determine specific distribution
  if [ "$UNAME" == "linux" ]; then
      # If available, use LSB to identify distribution
      if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
          export DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'// | tr '[:upper:]' '[:lower:]')
      # Otherwise, use release info file
      else
          export DISTRO=$(ls -d /etc/[A-Za-z]*[_-][rv]e[lr]* | grep -v "lsb" | cut -d'/' -f3 | cut -d'-' -f1 | cut -d'_' -f1 | tr '[:upper:]' '[:lower:]')
      fi
  fi
  # For everything else (or if above failed), just use generic identifier
  [ "$DISTRO" == "" ] && export DISTRO=$UNAME
  unset UNAME
}

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
  wait_for_file /home/$1/$3/bootstrap/$2.$1.crontab
  su $1 -c "cat /home/$1/$3/bootstrap/$2.$1.crontab | sort - | uniq - | crontab -"
}

setup_email () {
  setup_ask "email server"
  [ $? != 0 ] && return
  echo "Setting up email server"
  $install_command exim4 exim4-config mailutils
  dpkg-reconfigure exim4-config
  echo "What is the email username?"
  read email_user
  echo "What is the email password?"
  read -s email_pwd
  echo "What is the destination address?"
  read destination_email
  echo "*.hobbitton.at:$email_user:$email_pwd" >> /etc/exim4/passwd.client
  echo "$1: $email_user" >> /etc/email-addresses
  echo "$1@localhost: $email_user" >> /etc/email-addresses
  echo "$1@hostname1: $email_user" >> /etc/email-addresses
  echo "$1@hostname1.localdomain: $email_user" >> /etc/email-addresses
  echo "$1: $destination_email" >> /etc/aliases
  update-exim4.conf
  invoke-rc.d exim4 restart
  exim4 -qff
}

setup_flexget () {
  setup_ask "flexget daemon"
  [ $? != 0 ] && return
  $install_command python python-pip
  pip install --upgrade setuptools
  pip install flexget
}

setup_hostname () {
  setup_ask hostname
  [ $? != 0 ] && return
  echo "What is the hostname?"
  read hostname
  echo $hostname > /etc/hostname
  hostname $hostname
}

setup_kodi () {
  setup_ask "kodi media center"
  [ $? != 0 ] && return
  echo "Setting up Kodi media center"
  kodi_setting_folder=/home/$1/.kodi/userdata
  if [[ $DISTRO =~ .*ubuntu.* ]]
  then
    $install_command software-properties-common
    add_software_repo ppa:team-xbmc/ppa
    $refresh_pkg_command
  fi
  $install_command kodi lightdm
  wait_for_file /home/$1/$2/bootstrap/advancedsettings.xml.kodi
  wait_for_file /home/$1/$2/bootstrap/guisettings.xml.kodi
  wait_for_file /home/$1/$2/bootstrap/sources.xml.kodi
  su $1 -c "mkdir -p $kodi_setting_folder"
  su $1 -c "cp /home/$1/$2/bootstrap/advancedsettings.xml.kodi $kodi_setting_folder/advancedsettings.xml"
  su $1 -c "cp /home/$1/$2/bootstrap/guisettings.xml.kodi $kodi_setting_folder/guisettings.xml"
  su $1 -c "cp /home/$1/$2/bootstrap/sources.xml.kodi $kodi_setting_folder/sources.xml"
  rpl '#user-session=default' 'user-session=kodi' /etc/lightdm/lightdm.conf
  rpl '#autologin-user=' 'autologin-user=raph' /etc/lightdm/lightdm.conf
  rpl '#autologin-user-timeout=0' 'autologin-user-timeout=180' /etc/lightdm/lightdm.conf
  rpl '#autologin-session=' 'autologin-session=kodi' /etc/lightdm/lightdm.conf
  systemctl restart lightdm
}

setup_iptables () {
  setup_ask "iptables rules"
  [ $? != 0 ] && return
  echo "Setting iptables rules"
  wait_for_file /home/$1/$3/iptables/$2.iptables.sh
  wait_for_file /home/$1/$3/iptables/firewall_vars.sh
  su $1 -c "ln -s /home/$1/powercloud/binaries /home/$1/bin"
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
  $install_command openvpn
  wait_for_file /home/$1/keys/server/openvpn_server.$2.conf
  ln -s /home/$1/keys/server/openvpn_server.$2.conf /etc/openvpn/server.conf
  rpl 'ProtectHome=true' '#ProtectHome=true' /lib/systemd/system/openvpn@.service
  rpl 'LimitNPROC=10=10' '#LimitNPROC=10=10' /lib/systemd/system/openvpn@.service
  echo 1 > /proc/sys/net/ipv4/ip_forward
  rpl '#net.ipv4.ip_forward=1' 'net.ipv4.ip_forward=1' /etc/sysctl.conf
  systemctl enable openvpn@server.service
  systemctl start openvpn@server.service
}

setup_ssh () {
  setup_ask ssh
  [ $? != 0 ] && return
  mkdir /home/$1/.ssh
  wait_for_file /home/$1/$3/bootstrap/$2.$1.authorized_keys
  cat "/home/$1/$3/bootstrap/$2.$1.authorized_keys" >> /home/$1/.ssh/authorized_keys
  rpl '#PasswordAuthentication yes' 'PasswordAuthentication no' /etc/ssh/sshd_config
  rpl 'PermitRootLogin yes' 'PermitRootLogin no' /etc/ssh/sshd_config
  systemctl restart sshd.service
  chown $1:$1 /home/$1/.ssh/authorized_keys
  chmod 600 /home/$1/.ssh/authorized_keys
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
  perl -p -i -e 's/127\.0\.0\.1\:[0-9]{4,5}/0.0.0.0:8384/g' /home/$1/.config/syncthing/config.xml
  su $1 -c "./syncthing-linux-amd64-v0.14.36/syncthing > /dev/null 2>&1 &"
  cd $2
  echo "Now visit https://$HOSTNAME:8384 to configure syncthing"
  echo "Then press 'Enter' to resume the bootstrap..."
  read waiting
}

setup_system () {
  setup_ask system
  [ $? != 0 ] && return
  if [ "$2" == 't' ]
  then
    repo_type="testing"
  else
    repo_type="stable"
  fi
  echo "Updating and preparing system"
  apt-get update
  $install_command sudo git rpl psmisc rsync nano cron dialog htop cron-apt perl
  usermod -a -G sudo $1
  rpl jessie $repo_type /etc/apt/sources.list
  rpl stretch $repo_type /etc/apt/sources.list
  echo "Updating system, can take a long time..."
  apt-get update; apt-get -y dist-upgrade; apt-get -y autoremove
  echo 'MAILON="always"' >> /etc/cron-apt/config
  rpl '* * *' '* * 1' /etc/cron.d/cron-apt
  rpl 'Every night' 'Every week' /etc/cron.d/cron-apt
}

setup_stunnel () {
  setup_ask stunnel
  [ $? != 0 ] && return
  echo "Installing stunnel"
  $install_command stunnel4
  wait_for_file /home/$1/$3/bootstrap/$2.stunnel.conf
  cp /home/$1/$3/bootstrap/$2.stunnel.conf /etc/stunnel/stunnel.conf
  cp /home/$1/keys/server/stunnel.pem /etc/stunnel/
  rpl "ENABLED=0" "ENABLED=1" /etc/default/stunnel4
  systemctl enable stunnel4.service
  systemctl start stunnel4.service
}

setup_user () {
  setup_ask "user $1"
  [ $? != 0 ] && return
  echo "Creating user"
  adduser $1
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
