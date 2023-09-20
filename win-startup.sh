#!/bin/bash

BLUE='\e[1;34m'
NC='\e[0m' # No Color

set -euo pipefail

RAM="8200"
#Images
SERVER_IMG="win22-server"
CLIENT_IMG="win11"
#Workspace
LAB_NAME="win_lab"
#network config
GATEWAY="172.26.228.1"
SERVER_IP="172.26.228.2/23"
CLIENT_IP="172.26.228.3/23"
VLAN=""
SERVER_TAP=""
CLIENT_TAP=""

usage() {
>&2 cat << EOF
Usage: $0
   [ -v | --vlan <vlan id> ]
   [ -s | --server-port <server vm port number> ]
   [ -c | --client-port <client vm port number> ]
   [ -h | --help ]
EOF
exit 1
}

ARGS=$(getopt -a -o v:t:i:h --long vlan:,server-port:,client-port:,help -- "$@")

eval set -- "${ARGS}"
while :
do
    case $1 in
        -v | --vlan)
            VLAN=$2
            shift 2
            ;;
        -t | --server-port)
            SERVER_TAP=$2
            shift 2
            ;;
        -i | --client-port)
            CLIENT_TAP=$2
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        # -- means the end of the arguments; drop this, and break out of the while loop
        --)
            shift
            break
            ;;
        *) >&2 echo Unsupported option: "$1"
           usage
           ;;
      esac
done

if [[ -z "$VLAN" ]] || [[ "$VLAN" =~ [^[:digit:]] ]]; then
    echo "VLAN identifier is required"
    usage
fi

if [[ -z "$SERVER_TAP" ]] || [[ "$SERVER_TAP" =~ [^[:digit:]] ]]; then
    echo "Target tap port number is required"
    usage
fi

if [[ -z "$CLIENT_TAP" ]] || [[ "$CLIENT_TAP" =~ [^[:digit:]] ]]; then
    echo "Initiator tap port number is required"
    usage
fi

echo -e "~> ldap lab VLAN identifier: ${BLUE}${VLAN}${NC}"
echo -e "~> Target VM tap port number: ${BLUE}${SERVER_TAP}${NC}"
echo -e "~> Initiator VM tap port number: ${BLUE}${CLIENT_TAP}${NC}"
tput sgr0

# Switch ports configuration
for p in ${SERVER_TAP} ${CLIENT_TAP}
do
    echo "Configuring tap${p} port..."
    sudo ovs-vsctl set port tap${p} tag=${VLAN} vlan_mode=access
done

# Copy ldap server and client VMs image files
mkdir -p $HOME/vm/${LAB_NAME}
cd $HOME/vm/${LAB_NAME}/

cp_img() {
    local f="$1"
    img="${!f}.qcow2"
    echo "Copying ${img}"
    cp "$HOME/masters/${!f}.qcow2" "$HOME/vm/${LAB_NAME}/${f}.qcow2"
    cp "$HOME/masters/${!f}.qcow2_OVMF_VARS.fd" "$HOME/vm/${LAB_NAME}/${f}.qcow2_OVMF_VARS.fd"
}

for f in server_img client_img
do
    if [[ ! -f ${f^^}.qcow2 ]]
    then
        cp_img ${f^^} &
    fi
done

#wait for the end of the copy of the files 

wait

echo `ls`

#function to customize vm (network configuration and hostname)

customize_vm() {
    local vm="$1"
    local VM_IP="${vm^^}_IP"
    
    virt-customize -a "${vm}_img.qcow2" --run-command "sed -i 's_dhcp_static\n    address ${!VM_IP}\n    gateway ${GATEWAY}_' /etc/network/interfaces"
    virt-customize -a "${vm}_img.qcow2" --run-command "sed -i 's/vm0/${vm}/g' /etc/hosts /etc/hostname"
}

#parallelization of the configuration

# for vm in server client
# do
#     customize_vm "${vm}" &
# done

# echo "customizing Server img"
# virt-customize -a "SERVER_IMG.qcow2" --run-command "powershell -c 'mkdir test'"
# echo "done customizing"

# #wait for the process to finish to start the vm
# wait

for vm in SERVER CLIENT
do
    # Launch ldap server VM
    tap=${vm}_TAP
    img=${vm}_IMG
    $HOME/vm/scripts/ovs-startup.sh ${img}.qcow2 ${RAM} ${!tap} &
done

#wait for the launch of the vm
wait

exit 0
