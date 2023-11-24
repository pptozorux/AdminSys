#!/bin/bash

LAB_NAME="interco7_lab"

RAM=1024

echo "Lancement routeur Bleu ou Vert"

R1_02_PORT=639

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

for f in R1_02
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
auto enp0s1.201
iface enp0s1.201 inet static
    address 192.168.200.2/23 
    gateway 192.168.200.1
    dns-nameserver 172.16.0.2

iface enp0s1.201 inet6 static
    address 2001:678:3fc:c9::2/64
    gateway fe80:c9::1

# R1 -> R2
auto enp0s1.403
iface enp0s1.403 inet static
	address 10.2.12.1/29

# R1 -> R3
auto enp0s1.404
iface enp0s1.404 inet static
	address 10.2.13.1/29

# R1 -> lxd
auto asw-host
iface asw-host inet manual
	ovs_type OVSBridge
	ovs_ports sw-vlan21
	up ip link set dev \$IFACE up
	down ip link set dev \$IFACE down

allow-asw-host sw-vlan21
iface sw-vlan21 inet static
	ovs_type OVSBridge
	ovs_bridge asw-host
	ovs_options asw-host 21
	address 10.2.10.1/24

iface sw-vlan21 inet6 static
	ovs_type OVSBridge
	ovs_bridge asw-host
	ovs_options asw-host 21
	address fda0:7a62:15::1/64
' | sudo tee /etc/network/interfaces"

}

for vm in R1_02
do
    customize ${vm} &
done

wait 


for vm in R1_02
do
    # Launch ldap server VM
    tap=${vm^^}_PORT
    $HOME/vm/scripts/ovs-startup.sh ~/vm/${LAB_NAME}/${vm}.qcow2 ${RAM} ${!tap} &
done

wait

exit 0
