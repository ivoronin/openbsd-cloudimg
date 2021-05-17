#!/bin/sh

set -e

qemu-img convert -f raw -O vpc output-aws/disk.raw output-aws/disk.vhd
aws s3 cp output-aws/disk.vhd s3://openbsd-cloudimg/${IMAGE_NAME}.vhd

TASK_ID="$(aws ec2 import-snapshot --disk-container Format=vhd,UserBucket={S3Bucket=${BUCKET_NAME},S3Key=${IMAGE_NAME}.vhd} | jq -r '.ImportTaskId')"
echo "Started snapshot import task ${TASK_ID}"
while true; do
  OUTPUT="$(aws ec2 describe-import-snapshot-tasks --import-task-ids ${TASK_ID})"
  STATUS="$(echo ${OUTPUT} | jq -r '.ImportSnapshotTasks[0].SnapshotTaskDetail.Status')"
  echo "Snapshot import task status: ${STATUS}"
  if [ ${STATUS} = "active" ]; then
     sleep 15
     continue
  fi
  if [ ${STATUS} != "completed" ]; then
     echo "Unexpected status"
     exit 1
  fi
  SNAPSHOT_ID=$(echo ${OUTPUT} | jq -r '.ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId')
  if [ ${SNAPSHOT_ID} = "" ]; then
     echo "Failed to get snapshot id"
     exit 1
  fi
  break
done

echo "Successfully imported snapshot ${SNAPSHOT_ID}"

aws ec2 register-image --name ${IMAGE_NAME} --root-device-name /dev/sda1 \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={SnapshotId=${SNAPSHOT_ID}}" \
  --virtualization-type hvm --no-ena-support --architecture x86_64

echo "Successfully registered image ${IMAGE_NAME}"

aws s3 rm s3://openbsd-cloudimg/${IMAGE_NAME}.vhd

rm -rf output-aws
