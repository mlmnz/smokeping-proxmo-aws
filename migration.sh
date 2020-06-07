#!/bin/bash

#Useful variables
VMSTOPSTA="stopped"
TIMEOUT=0
VHD_IMAGE=vm.vhd
AWS_S3_BUCKET=mlmnz-mybucket
AWS_IMPORT_TASK_STATUS="completed"

taskId=""
snapshopId=""

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
 

 if [ $TIMEOUT -gt 60 ]
 then
    exit 1
 fi
 echo $TIMEOUT
 sleep 2
 TIMEOUT=$(($TIMEOUT + 2))
done

###################
# Export VM Diskimage
##################
# Create a VHD image
echo "Exporting VM disk as VHD image"
qemu-img convert -f raw -O vpc /dev/zvol/rpool/vm-$vmid-disk-0 /root/$VHD_IMAGE

# Create a S3 Bucket and upload the VHD image.
echo "Create a New S3 Bucket and upload the VHD image"
aws s3 mb s3://$AWS_S3_BUCKET
aws s3 cp  /root/$VHD_IMAGE s3://$AWS_S3_BUCKET


###################
# Snapshot from VHD image
##################
echo "Create a snapshot from VHD image stored in S3"

# Exec the task, and keep in mind the id
taskId=`aws ec2 import-snapshot \
    --disk-container "Format=vhd,UserBucket={S3Bucket=$AWS_S3_BUCKET,S3Key=$VHD_IMAGE}" | \
    tee /dev/tty | awk '/"ImportTaskId"/ {print substr($2, 2, length($2)-3)}' `

# Monitoring task process and check if completed.
echo -e "Create a task with id: $taskId \n"
taskDone="False"
while [[ $taskDone == "False" ]]
do
 taskStatus=`aws ec2 describe-import-snapshot-tasks --import-task-ids $taskId | \
 tee /dev/tty | awk '/"Status"/ {print substr($2, 2, length($2)-3)}'`

# If task is completed, get the snap id
if [[ $taskStatus == $AWS_IMPORT_TASK_STATUS ]]
then
  snapshopId=`aws ec2 describe-import-snapshot-tasks --import-task-ids $taskId | \
  awk '/"SnapshotId"/ {print substr($2, 2, length($2)-3)}'`
  taskDone="True"
fi
sleep 2
done