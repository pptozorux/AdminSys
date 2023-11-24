#!/bin/bash

LAB_NAME="interco7_lab"

RAM=1024

echo "Lancement routeur Bleu ou Vert"

HUB_PORT=639

MASTER_IMG_NAME="debian-testing-amd64"

config_port(){
    local tap="${1}_PORT"
    echo "Configuring tap${!tap} port..."
    sudo ovs-vsctl set port tap${!tap} vlan_mode=trunk

}

for vm in HUB 
do
    config_port ${vm} &
done 

wait

# Copy ldap server and router VMs image files
mkdir -p $HOME/vm/${LAB_NAME}
cd $HOME/vm/${LAB_NAME}/


cp_img() {
    local f="$1"
    echo "Copying ${f}.qcow2 image file..."
    cp $HOME/masters/${MASTER_IMG_NAME}.qcow2 $HOME/vm/${LAB_NAME}/${f}.qcow2
    cp $HOME/masters/${MASTER_IMG_NAME}.qcow2_OVMF_VARS.fd $HOME/vm/${LAB_NAME}/${f}.qcow2_OVMF_VARS.fd
}

for f in HUB
do
    if [[ ! -f ${f}.qcow2 ]]
    then
        cp_img ${f} &
    fi
done

#wait for the end of the copy of the files 

wait

customize() {
    local vm="$1"
    echo "Customizing ${vm} hostname..."
    virt-customize -a "$HOME/vm/${LAB_NAME}/${vm}.qcow2" --run-command "sed -i 's/vm0/${vm}/g' /etc/hosts /etc/hostname"

    virt-customize -a "$HOME/vm/${LAB_NAME}/${vm}.qcow2" --run-command "echo '# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback
# The primary network interface
auto enp0s1
iface enp0s1 inet manual
    up ip link set dev \$IFACE up
    down ip link set dev \$IFACE down

# ---------- VLAN ROUGE ----------
auto enp0s1.131
iface enp0s1.131 inet static
    address 10.0.131.2/25
    gateway 10.0.131.1
    dns-nameserver 172.16.0.2

iface enp0s1.131 inet6 static
    address 2001:678:3fc:83::2/64
    gateway fe80:83::1

# ---------- VLAN VIOLET SPOKE 1 -
auto enp0s1.473
iface enp0s1.473 inet6 static
    address fe80:1D9::1/64

# ---------- VLAN ORANGE SPOKE 1 -
auto enp0s1.474
iface enp0s1.474 inet manual
    up ip link set dev \$IFACE up
    up pppoe-server -I \$IFACE -C BRAS -L 10.22.22.1 -R 10.22.22.2 -N 1 -u 0
    down killall pppoe-server
    down ip link set dev \$IFACE down

# ---------- VLAN VIOLET SPOKE 2 -
auto enp0s1.475
iface enp0s1.475 inet6 static
    address fe80:1DB::1/64

# ---------- VLAN ORANGE SPOKE 2 -
auto enp0s1.476
iface enp0s1.476 inet manual
    up ip link set dev \$IFACE up
    up pppoe-server -I \$IFACE -C BRaS -L 10.23.22.1 -R 10.23.22.2 -N 1 -u 1
    down killall pppoe-server
    down ip link set dev \$IFACE down' | sudo tee /etc/network/interfaces"

}

for vm in HUB
do
    customize ${vm} &
done

wait 


for vm in HUB
do
    # Launch ldap server VM
    tap=${vm^^}_PORT
    $HOME/vm/scripts/ovs-startup.sh ~/vm/${LAB_NAME}/${vm}.qcow2 ${RAM} ${!tap} &
done

wait

exit 0
