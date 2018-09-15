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
echo "Do you want to use the (s)table or (t)esting repositories? (s/t)"
read repo
init_folder=`dirname "$0"`
cd $init_folder && init_folder=`pwd`
. $init_folder/lib/utils.sh

detect_distro
setup_hostname
setup_user "$user"
setup_system "$user" "$repo"
setup_syncthing "$user" "$init_folder"
setup_bitpocket "$user" "$model" "$bs_folder"
#TODO: Need to setup bitpocket https://github.com/sickill/bitpocket/blob/master/bin/bitpocket
setup_ssh "$user" "$model" "$bs_folder"
setup_crontab "$user" "$model" "$bs_folder"
setup_iptables "$user" "$model" "$bs_folder"
setup_email "$user"
setup_kodi "$user" "$bs_folder"
setup_openvpn_server "$user" "$model"
setup_stunnel "$user" "$model" "$bs_folder"
setup_searx "$user" "$bs_folder"
echo "All done, bye"
