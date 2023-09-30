#!/bin/bash

BLUE='\e[1;34m'
NC='\e[0m' # No Color

set -euo pipefail

RAM="1024"
VLAN=""
TARGET_TAP=""
INITIATOR_TAP=""
MASTER_IMG_NAME="debian-testing-amd64"
LAB_NAME="iscsi_lab"
SECOND_DISK_SIZE="32G"

#network config
GATEWAY="10.0.238.225"
TARGET_IP="10.0.238.226/28"
INITIATOR_IP="10.0.238.227/28"

usage() {
>&2 cat << EOF
Usage: $0
   [ -v | --vlan <vlan id> ]
   [ -t | --target-port <target vm port number> ]
   [ -i | --initiator-port <initiator vm port number> ]
   [ -h | --help ]
EOF
exit 1
}

ARGS=$(getopt -a -o v:t:i:h --long vlan:,target-port:,initiator-port:,help -- "$@")

eval set -- "${ARGS}"
while :
do
    case $1 in
        -v | --vlan)
            VLAN=$2
            shift 2
            ;;
        -t | --target-port)
            TARGET_TAP=$2
            shift 2
            ;;
        -i | --initiator-port)
            INITIATOR_TAP=$2
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

if [[ -z "$TARGET_TAP" ]] || [[ "$TARGET_TAP" =~ [^[:digit:]] ]]; then
    echo "Target tap port number is required"
    usage
fi

if [[ -z "$INITIATOR_TAP" ]] || [[ "$INITIATOR_TAP" =~ [^[:digit:]] ]]; then
    echo "Initiator tap port number is required"
    usage
fi

echo -e "~> iSCSI lab VLAN identifier: ${BLUE}${VLAN}${NC}"
echo -e "~> Target VM tap port number: ${BLUE}${TARGET_TAP}${NC}"
echo -e "~> Initiator VM tap port number: ${BLUE}${INITIATOR_TAP}${NC}"
tput sgr0

# Switch ports configuration
for p in ${TARGET_TAP} ${INITIATOR_TAP}
do
    echo "Configuring tap${p} port..."
    sudo ovs-vsctl set port tap${p} tag=${VLAN} vlan_mode=access
done

# Copy iSCSI target and initiator VMs image files
mkdir -p $HOME/vm/${LAB_NAME}
cd $HOME/vm/${LAB_NAME}/

cp_img() {
    local f="$1"
    echo "Copying ${f}.qcow2 image file..."
    cp $HOME/masters/${MASTER_IMG_NAME}.qcow2 $HOME/vm/${LAB_NAME}/${f}.qcow2
    cp $HOME/masters/${MASTER_IMG_NAME}.qcow2_OVMF_VARS.fd $HOME/vm/${LAB_NAME}/${f}.qcow2_OVMF_VARS.fd
}

for f in target_img initiator_img
do
    if [[ ! -f ${f}.qcow2 ]]; then
        cp_img ${f} &
    fi
done


create_disk(){
    local f="${1}"
    echo "Creating ${f}.qcow2 disk..."
    qemu-img create -f qcow2 \
    -o lazy_refcounts=on,extended_l2=on,compression_type=zstd \
    $HOME/vm/${LAB_NAME}/${f}.qcow2 ${SECOND_DISK_SIZE}
}

# Create second disk for each VM
for f in target_vol initiator_vol
do
    if [[ ! -e ${f}.qcow2 ]]; 
    then
        create_disk ${f} &
    fi
done

wait

#function to customize vm (network configuration and hostname)

customize_vm() {
    local vm="$1"
    local VM_IP="${vm^^}_IP"
    
    virt-customize -a "${vm}_img.qcow2" --run-command "sed -i 's_dhcp_static\n    address ${!VM_IP}\n    gateway ${GATEWAY}_' /etc/network/interfaces"
    virt-customize -a "${vm}_img.qcow2" --run-command "sed -i 's/vm0/${vm}/g' /etc/hosts /etc/hostname"
}

#parallelization of the configuration

for vm in target initiator
do
    customize_vm "${vm}" &
done


#wait for the process to finish to start the vm
wait

for vm in target initiator
do
    # Launch iSCSI target VM
    tap=${vm^^}_TAP
    $HOME/vm/scripts/ovs-startup.sh ${vm}_img.qcow2 ${RAM} ${!tap} \
        -drive if=none,id=${vm}_disk,format=qcow2,media=disk,file=${vm}_vol.qcow2 \
        -device virtio-blk,drive=${vm}_disk,scsi=off,config-wce=off \
        &
done

exit 0
