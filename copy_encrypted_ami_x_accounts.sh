#!/bin/bash
#
# Copyright 2017 Pixelworks Inc.
#
# Author: Simon Cheng Chi <cchi@pixelworks.com>
# Re-arranged by: Houyu Li <hyli@pixelworks.com>
#
# This script is to simplify the process of copying encrypted AMI from one
# AWS account to another. The process is described at
# https://aws.amazon.com/blogs/security/how-to-create-a-custom-ami-with-encrypted-amazon-ebs-snapshots-and-share-it-with-other-accounts-and-regions/
# Before start, you should have AWS command line tool installed, and setup
# profile with access / secret keys of IAM user with proper permission for
# each AWS account.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#**************** Modify variables below to match your task ****************

## The source AMI ID.
## This is required.
AMI_ID_SRC=""
if [ -z $AMI_ID_SRC ]; then
    echo "You MUST specify the source AMI image ID!" >&2
    exit 1
fi
## //

## AWS command line tool profile for source account and destination account.
## By default, we use source account profile for destination account.
AWSCLI_PROF_SRC="--profile default"
AWSCLI_PROF_DST="$AWSCLI_PROF_SRC"
#AWSCLI_PROF_DST="--profile dest"
## //

## Account ID for source account and destination account.
## By default, we use source account ID for destination account ID. 
AWS_ACCT_ID_SRC=000000000000
AWS_ACCT_ID_DST=$AWS_ACCT_ID_SRC
#AWS_ACCT_ID_DST=000000000000
## //

## Region for copying AMI / snapshot from and to.
## By default, we use same region.
REGION_FROM="us-west-2"
REGION_TO="$REGION_FROM"
#REGION_TO="us-west-2"
## //

## KMS key ID for encrypting source and destination snapshots.
KMS_ID_SRC="00000000-0000-0000-0000-000000000000"
KMS_ID_DST="00000000-0000-0000-0000-000000000000"
## //

#**************** Do not modify anything below this line ****************

date

aws --profile $SRC_P ec2 describe-images --image-ids $SOURCE_AMI  &>/dev/null || \
	{ echo "AMI not exisit" ; exit 0; }

NEW_NAME=$(aws --profile $SRC_P ec2 describe-images --image-ids $SOURCE_AMI --query Images[].Name --output text)
NEW_DESCRIPTION=$(aws --profile $SRC_P ec2 describe-images --image-ids $SOURCE_AMI --query Images[].Description --output text)

## check if the name of AMI exist in DST 
TMP_DST_AMI_ID=$(aws --profile $DST_P ec2 describe-images --filter Name=name,Values="$NEW_NAME" --query Images[].ImageId --output text)
[ "$TMP_DST_AMI_ID" != "" ]  && { echo "AMI name exist in DST"; exit 0; }




TMP_NAME=$SOURCE_AMI.tmp

TMP_SOURCE_AMI=$(aws --profile $SRC_P ec2 copy-image --encrypted --kms-key-id $SOURCE_KMS_ID --name $TMP_NAME --source-image-id $SOURCE_AMI --source-region $SOURCE_REGION --query ImageId --output text)



PERCENTAGE=""
while [ "$PERCENTAGE" != "100%" ]
do
sleep 10
PERCENTAGE=$(aws --profile $SRC_P ec2 describe-snapshots --filters Name=description,Values=\*$TMP_SOURCE_AMI\* --query Snapshots[].Progress --output text)
done
 
SRC_SNAP_ID=$(aws --profile $SRC_P ec2 describe-snapshots --filters Name=description,Values=\*$TMP_SOURCE_AMI\* --query Snapshots[].SnapshotId --output text)

#echo "SNAP="$SRC_SNAP_ID

aws --profile $SRC_P ec2 modify-snapshot-attribute --attribute createVolumePermission --operation-type add --snapshot-id $SRC_SNAP_ID --user-ids $TARGET_ID


TMP_DESCRIPTION="simoncopy2"
DST_SNAP_ID=$(aws --region $TARGET_REGION --profile $DST_P ec2 copy-snapshot --source-region $SOURCE_REGION --source-snapshot-id $SRC_SNAP_ID --description $TMP_DESCRIPTION --encrypted --kms-key-id $TARGET_KMS_ID --query SnapshotId --output text)

PERCENTAGE=""
while [ "$PERCENTAGE" != "100%" ]
do
sleep 10
PERCENTAGE=$(aws --profile $DST_P ec2 describe-snapshots --snapshot-ids $DST_SNAP_ID --query Snapshots[].Progress --output text)
done



NEW_AMI_ID=$(aws --region $TARGET_REGION --profile $DST_P ec2 register-image --architecture x86_64 --root-device-name /dev/sda1 --block-device-mappings DeviceName=/dev/sda1,Ebs={SnapshotId=$DST_SNAP_ID} --description "$NEW_DESCRIPTION" --name $NEW_NAME --virtualization-type hvm --query ImageId --output text)


echo $NEW_AMI_ID 


###now cleanup
aws --profile $SRC_P ec2 deregister-image --image-id $TMP_SOURCE_AMI
aws --profile $SRC_P ec2 delete-snapshot --snapshot-id $SRC_SNAP_ID

date