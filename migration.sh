#!/bin/bash

###################
# Useful varibles
###################
VMSTOPSTA="stopped"
TIMEOUT=0
VHD_IMAGE=vm.vhd
AWS_S3_BUCKET=mlmnz-mybucket
AWS_IMPORT_TASK_STATUS="completed"

AWS_SG="my-security-group"
AWS_KEYPAIRS="my-keypairs"

taskId=""
snapshopId=""
imageId=""
instanceId=""
instanceState=""
ipAddress=""


echo "Migration script to export and launch a VM from Proxmox to AWS"
######################################
# Proxmox Image Selection
######################################

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

######################################
# Export VM Diskimage
#####################################
# Create a VHD image
echo "Exporting VM disk as VHD image"
qemu-img convert -f raw -O vpc /dev/zvol/rpool/vm-$vmid-disk-0 /root/$VHD_IMAGE

# Create a S3 Bucket and upload the VHD image.
echo "Create a New S3 Bucket and upload the VHD image"
aws s3 mb s3://$AWS_S3_BUCKET
aws s3 cp  /root/$VHD_IMAGE s3://$AWS_S3_BUCKET


######################################
# Snapshot from VHD image
#####################################
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

######################################
# AMI creation from Snapshot
#####################################
echo -e "Creating an AMI with previous snapshot id: $snapshopId"
imageId=`aws ec2 register-image \
    --name "Alpine-3.10-custom" \
    --description "Custom Alpine image" \
    --architecture x86_64 \
    --virtualization-type "hvm" \
    --block-device-mappings "DeviceName="/dev/sda1",Ebs={SnapshotId=$snapshopId}" \
    --root-device-name "/dev/sda1" | \
    awk '/"ImageId"/ {print substr($2, 2, length($2)-2)}'`
echo -e "Succeful AMI creation with id: $imageId"


######################################
# EC2 Security Groups, Keypairs
#####################################

#Generate key pair and set read/write  permissions to owner
echo "We need create a security group and a key pairs for the AWS Instance"
aws ec2 create-key-pair --key-name $AWS_KEYPAIRS | \
awk -F ":" ' /"KeyMaterial"/{print substr($2,3,length($2)-4)}' | \
awk  '{gsub("\\\\n","\n")};1' >  ~/.ssh/$AWS_KEYPAIRS
echo -e "The keypair '$AWS_KEYPAIRS' was created succefully, was store in ~/.ssh/ directory"
chmod 600 ~/.ssh/$AWS_KEYPAIRS

#Create the security group and ingress rules
aws ec2 create-security-group \
    --group-name $AWS_SG \
    --description "My security group"

## SSH allow
aws ec2 authorize-security-group-ingress \
    --group-name $AWS_SG \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

## HTTP allow
aws ec2 authorize-security-group-ingress \
    --group-name $AWS_SG \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0


######################################
# EC2 Instance
#####################################

instanceId=`aws ec2 run-instances \
    --image-id $imageId \
    --count 1 --instance-type t2.micro \
    --key-name $AWS_KEYPAIRS \
    --security-groups $AWS_SG | \
     awk '/"InstanceId"/ {print substr($2,2,length($2)-3)}'`


echo -e "The instance was succefully created, with id: $instanceId"
echo "Wait for instace is in running state"
while [[ $instanceState == "16" ]] #Running code
do
   instanceState=`aws ec2 describe-instances --instance-ids $intanceId | \
   awk '/"Code"/ {print substr($2,1,length($2)-1)}'`
   echo $instaceState
   sleep 1
done

# Get the Public IP when instances is running
ipAddress=`aws ec2 describe-instances --instance-ids $intanceId | \
awk '/"PublicIpAddress"/ {print substr($2,1,length($2)-1)}'`
echo -e "Task finished. You can connect to instace with the IP Address:$ipAddress \n
SSH  -> ssh -i "$AWS_KEYPAIRS" root@$ipAddress \n
HTTP -> http://$ipAddress/