#!/bin/env sh

PROG_NAME="$0"
COPY_NUM=10
IMAGE_ID=""
INSTANCE_TYPE=""
AVAILABILITY_ZONE=""
CREDENTIAL=""
SECURITU_GROUP=""
COPY_DIR="/data"
INSTANCE_ID=$1
VERBOSE="false"

usage() {
    echo "$PROG_NAME [-hv] [-d dir] [-n num] instance
    -d dir   Copy the contents of this data directory from the orignal source
	      instance to all the new instances.  If not specified, defaults
	      to /data.
    -h       Print a usage statement and exit.

    -n num   Create this many new instances.  If not specified, defaults to
	      10.

    -v       Be verbose."
}

show_config() {
    echo "copy number: $COPY_NUM"
    echo "copy directory: $COPY_DIR"
    echo "instance id: $INSTANCE_ID"
}

create_instance() {
    echo "create instance:"
    IMAGE_ID=`aws ec2 describe-instances --instance-ids $INSTANCE_ID --query Reservations[].Instances[].ImageId | sed 's/\"//g' | grep [[:alnum:]]`
    CREDENTIAL=`aws ec2 describe-instances --instance-ids $INSTANCE_ID --query Reservations[].Instances[].KeyName | sed 's/\"//g' | grep "[[:alnum:]]"`
    SECURITU_GROUP=`aws ec2 describe-instances --instance-ids $INSTANCE_ID --query Reservations[].Instances[].SecurityGroups[].GroupId | sed 's/\"//g' | grep "[[:alnum:]]"`
    AVAILABILITY_ZONE=`aws ec2 describe-instances --instance-ids $INSTANCE_ID --query Reservations[].Instances[].Placement.AvailabilityZone | sed 's/\"//g' | grep "[[:alnum:]]"`
    INSTANCE_TYPE=`aws ec2 describe-instances --instance-ids $INSTANCE_ID --query Reservations[].Instances[].InstanceType | sed 's/\"//g' | grep "[[:alnum:]]"`
    
    echo $IMAGE_ID
    echo $CREDENTIAL
    echo $SECURITU_GROUP
    echo $AVAILABILITY_ZONE
    echo $INSTANCE_TYPE

    for i in $(seq 1 $COPY_NUM);
    do
    aws ec2 run-instances --image-id $IMAGE_ID --security-group-ids $SECURITU_GROUP --count 1 --placement AvailabilityZone="$AVAILABILITY_ZONE" --instance-type $INSTANCE_TYPE --key-name $CREDENTIAL
    done
}

#create_instance $1

while true ; do
    case "$2" in
        -h) usage ; exit 0 ;;
        -d) shift ; COPY_DIR=$2 ; shift ;;
        -n) shift ; COPY_NUM=$2 ;
                    create_instance ; shift ;;
        -v) shift ; VERBOSE="true" ;;
        -*) echo "Invalid option $1"; usage ; exit 1 ;;
        *)
            if [ "$#" != "0" ] && [ "$INSTANCE_ID" != "" ] ; then
                echo "Unknown options: $@"
                usage
                exit 1
            elif [ "$#" != "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                INSTANCE_ID="$1"
                shift
            elif [ "$#" == "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                echo "Instance not specified."
                usage
                exit 1
            else
                show_config
                exit 0
            fi ;;
    esac
done
