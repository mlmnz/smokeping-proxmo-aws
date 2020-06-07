#!/bin/bash

#Useful variables
VMSTOPSTA="stopped"
TIMEOUT=0
VHD_IMAGE=vm.vhd
AWS_S3_BUCKET=mlmnz-mybucket

echo "Migration script to export and launch a VM from Proxmox to AWS"
###################
# Proxmox Image Selection
###################

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
qemu-img convert -f raw -O vpc /dev/zvol/rpool/vm-$vmid-disk-0 /root/$VHD_IMAGE

# Create a S3 Bucket and upload the VHD image.
aws s3 mb s3://$AWS_S3_BUCKET
aws s3 cp  /root/$VHD_IMAGE s3://$AWS_S3_BUCKET