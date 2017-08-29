#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "What is the username for the system user?"
read user
echo "What is the model system name?"
read model
echo "What is the bootstrap folder? (/home/$user/?)"
read bs_folder
init_folder=`dirname "$0"`
cd $init_folder && init_folder=`pwd`
. $init_folder/lib/utils.sh

setup_hostname
setup_user "$user"
setup_system "$user"
setup_syncthing "$user" "$init_folder"
setup_ssh "$user" "$model" "$bs_folder"
setup_crontab "$user" "$model" "$bs_folder"
setup_iptables "$user" "$model" "$bs_folder"
setup_email "$user"
setup_openvpn_server "$user"
echo "All done, bye"
