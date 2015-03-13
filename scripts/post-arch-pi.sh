#!/bin/sh

# This file can be downloaded at http://tinyurl.com/oyuh92j
######################################
# To build the sd card, follow instructions @ http://archlinuxarm.org/platforms/armv6/raspberry-pi
# Then run this script.
# After boot, one can log a s `root` (password = `root`)
# And run: `systemctl start slim` to start the window manager
######################################

set -e # stop if any error happens

USER_NAME=psv
PASSWORD=psv
PSV_DATA_DIR=/psv_data
PSV_DB_NAME=psv_db

############# PACKAGES #########################
echo 'Installing and updating packages'

# pacman-db-update
# pacman-key --init
pacman -Syu --noconfirm
pacman -S base-devel git gcc-fortran rsync wget --noconfirm --needed
### Video capture related
pacman -S opencv mplayer ffmpeg gstreamer gstreamer0.10-plugins mencoder --noconfirm --needed
# a desktop environment may be useful:
pacman -S xorg-server xorg-utils xorg-server-utils xorg-xinit xf86-video-fbdev lxde slim --noconfirm --needed
# utilities
pacman -S ntp bash-completion --noconfirm --needed
pacman -S raspberrypi-firmware{,-tools,-bootloader,-examples} --noconfirm --needed

# preinstalling dependencies will save compiling time on python packages
pacman -S python2-pip python2-numpy python2-bottle python2-pyserial mysql-python python2-cherrypy --noconfirm --needed

# mariadb
pacman -S mariadb --noconfirm --needed

#setup Wifi dongle
#pacman -S netctl
pacman -S wpa_supplicant --noconfirm --needed


echo 'Description=psv wifi network' > /etc/netctl/psv_wifi
echo 'Interface=wlan0' >> /etc/netctl/psv_wifi
echo 'Connection=wireless' >> /etc/netctl/psv_wifi
echo 'Security=wpa' >> /etc/netctl/psv_wifi
echo 'IP=dhcp' >> /etc/netctl/psv_wifi
echo 'ESSID=psv_wifi' >> /etc/netctl/psv_wifi
# Prepend hexadecimal keys with \"
# If your key starts with ", write it as '""<key>"'
# See also: the section on special quoting rules in netctl.profile(5)
echo 'Key=PSV_WIFI_pIAEZF2s@jmKH' >> /etc/netctl/psv_wifi
# Uncomment this if your ssid is hidden
#echo 'Hidden=yes'

######################################################################################
echo 'Description=eth0 Network' > /etc/netctl/eth0
echo 'Interface=eth0' >> /etc/netctl/eth0
echo 'Connection=ethernet' >> /etc/netctl/eth0
echo 'IP=dhcp' >> /etc/netctl/eth0
######################################################################################


#Updating ntp.conf

echo 'server 192.169.123.1' > /etc/ntp.conf
echo 'server 127.0.0.0' >> /etc/ntp.conf
echo 'restrict default kod limited nomodify nopeer noquery notrap' >> /etc/ntp.conf
echo 'restrict 127.0.0.1' >> /etc/ntp.conf
echo 'restrict ::1' >> /etc/ntp.conf
echo 'driftfile /var/lib/ntp/ntp.drift' >> /etc/ntp.conf

######################################################################################

#Creating service for device_server.py

cp ./device.service /etc/systemd/system/device.service

systemctl daemon-reload
######################################################################################
echo 'Enabling startuup deamons'

systemctl disable systemd-networkd
ip link set eth0 down
# Enable networktime protocol
systemctl start ntpd.service
systemctl enable ntpd.service
# Setting up ssh server
systemctl enable sshd.service
systemctl start sshd.service
#setting up wifi
#Fixme this does not work if the pi is not connected to a psv_wifi
#netctl start psv_wifi
netctl enable psv_wifi
netctl start psv_wifi
netctl enable eth0
netctl start eth0

#device service
systemctl start device.service
systemctl enable device.service


#TODO s: locale/TIMEZONE/keyboard ...

##########################################################################################
# add password without stoping
echo 'Creating default user'

pass=$(perl -e 'print crypt($ARGV[0], "password")' $PASSWORD)
useradd -m -g users -G wheel -s /bin/bash  -p $pass $USER_NAME || echo 'warning: user exists'

echo 'exec startlxde' >> /home/$USER_NAME/.xinitrc
chown $USER_NAME /home/$USER_NAME/.xinitrc

# Setting passwordless ssh, this is the content of id_rsa (private Key on node).
mkdir -p /home/$USER_NAME/.ssh
#TODO do not use a relative path.
cp ./ssh_keys/id_rsa /home/$USER_NAME/.ssh/id_rsa
chmod 600 /home/$USER_NAME/.ssh/id_rsa
# copy to root keys as well!!
cp ./ssh_keys/id_rsa /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

############################################
echo 'Generating boot config'

echo 'start_file=start_x.elf' > /boot/config.txt
echo 'fixup_file=fixup_x.dat' >> /boot/config.txt
echo 'disable_camera_led=1' >> /boot/config.txt
#gpu_mem_512=64
#gpu_mem_256=64


###Turbo #FIXME NOT needed for piv2.0
#echo 'arm_freq=1000' >> /boot/config.txt
#echo 'core_freq=500' >> /boot/config.txt
#echo 'sdram_freq=500' >> /boot/config.txt
#echo 'over_voltage=6' >> /boot/config.txt

### TODO test, is that enough?
echo 'gpu_mem=256' >>  /boot/config.txt
echo 'cma_lwm=' >>  /boot/config.txt
echo 'cma_hwm=' >>  /boot/config.txt
echo 'cma_offline_start=' >>  /boot/config.txt


echo 'Loading bcm2835 module'

#to use the camera through v4l2
# modprobe bcm2835-v4l2
echo "bcm2835-v4l2" > /etc/modules-load.d/picamera.conf

echo 'Setting permissions for using arduino'
#SEE https://wiki.archlinux.org/index.php/arduino#Configuration
gpasswd -a $USER_NAME uucp
gpasswd -a $USER_NAME lock
gpasswd -a $USER_NAME tty


###########################################################################################
# The hostname is derived from the **eth0** MAC address, NOT the wireless one
#mac_addr=$(ip link show  eth0  |  grep -ioh '[0-9A-F]\{2\}\(:[0-9A-F]\{2\}\)\{5\}' | head -1 | sed s/://g)
# The hostname is derived from the **machine-id**, located in /etc/machine-id

device_id=$(cat /etc/machine-id)
hostname=PI_$device_id
echo "Hostname is $hostname"
hostnamectl set-hostname $hostname



echo "setting up mysql"
mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
systemctl enable mysqld.service
systemctl start mysqld.service

## not even useful:
#mysql -u root -e "create database $PSV_DB_NAME";

mysql -u root -e "CREATE USER \"$USER_NAME\"@'localhost' IDENTIFIED BY \"$PASSWORD\""
mysql -u root -e "CREATE USER \"$USER_NAME\"@'%' IDENTIFIED BY \"$PASSWORD\""
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO \"$USER_NAME\"@'localhost' WITH GRANT OPTION";
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO \"$USER_NAME\"@'%' WITH GRANT OPTION";


# This disables binary logs to save on I/O, space
# 1 backup:
cp /etc/mysql/my.cnf  /etc/mysql/my.cnf-bak
# remove log-bin lines
cat /etc/mysql/my.cnf-bak | grep -v log-bin >  /etc/mysql/my.cnf

###############mysql -u root -e "SET GLOBAL expire_logs_days = 2"
#partitions stuff
# make partition system
#cd /mnt/
#mkdir sda_var pi_var
#mount /dev/sda2 /mnt/sda_var
#mount /dev/mmXXX  /mnt/pi_var
#cp -ax /mnt/pi_var/* /mnt/sda_var
#echo "" >> /etc/fstab

####################

##########
#Create a local working copy from the bare repo on node (192.168.123.1)
echo 'Cloning from Node'

# FIXME this needs a node in the network to set up the psv
git clone node@192.169.123.1:/var/pySolo-Video.git /home/$USER_NAME/pySolo-Video


# our software.
# TODO use AUR!
echo 'Installing PSV package'
#wget https://github.com/gilestrolab/pySolo-Video/archive/psv_prerelease.tar.gz -O psv.tar.gz
#tar -xvf psv.tar.gz
cd /home/psv/pySolo-Video/src
pip2 install -e .



echo "copying var part"
mkdir -p $PSV_DATA_DIR
chmod 744 $PSV_DATA_DIR -R



#### set the ssd
echo "o
n
p


+14G

n
p



w
" | fdisk /dev/sda

mkfs.ext4 /dev/sda1
mkfs.ext4 /dev/sda2
mkdir -p $PSV_DATA_DIR
chmod 744 $PSV_DATA_DIR -R
mount /dev/sda2 $PSV_DATA_DIR
cp /etc/fstab /etc/fstab-bak
echo "/dev/sda1 /var ext4 defaults,rw,relatime,data=ordered 0 1" >> /etc/fstab
echo "/dev/sda2 $PSV_DATA_DIR ext4 defaults,rw,relatime,data=ordered 0 1" >> /etc/fstab
mkdir /mnt/var
mount /dev/sda1 /mnt/var
#init 1
cd /var
cp -ax * /mnt/var
cd /
mv var var.old
mkdir /var
umount /dev/sda1
mount /dev/sda1 /var
echo 'SUCESS, please reboot'