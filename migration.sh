#!/bin/bash

#Useful variables
VMSTOPSTA="stopped"
TIMEOUT=0
AWS_S3_BUCKET=mybucket

echo "Migration script to export and launch a VM from Proxmox to AWS"

# VM ID selection
qm list
echo "Which VM want export to AWS? write the VMID number"
read vmid

#Stop the VM
echo "Stopping VM with VMID:$vmid if it was started"
qm shutdown $vmid
VMstatus=`qm list | grep $vmid | awk '{print $3}'`

#Wait for 60s to stope the WM, if not  trhow error.
while [[ $VMstatus != "stopped" ]]
do
 VMstatus=`qm list | grep $vmid | awk '{print $3}'`
 TIMEOUT=$(($TIMEOUT + 2))

 if [ $TIMEOUT -gt 60 ]
 then
    exit 1
 fi
 echo $TIMEOUT
done

###################
# Export VM Diskimage
##################
# Create a VHD image
echo "Exporting VM disk as VHD image"
vmdisk=`echo vm-$vmid-disk-0`
qemu-img convert -f raw -O vpc /dev/zvol/rpool/$vmdisk /root/vm.vhd

# Create a S3 Bucket