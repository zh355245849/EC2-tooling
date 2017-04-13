#!/bin/bash

PROG_NAME="afewmore"
TASK_FILE="task.0"
PEM_FILE=$PEM_FILE_PATH

COPY_NUM=1
COPY_DIR="/data"
INSTANCE_ID=""
VERBOSE="false"

usage() {
    echo "usage: $PROG_NAME [-hv] [-d dir] [-n num] instance"
    echo "                -d dir   Copy the contents of this data directory from the"
    echo "                         orignal source instance to all the new instances."
    echo "                         If not specified, defaults to \"/data\"."
    echo "                -h       Print a usage statement and exit."
    echo "                -n num   Create this many new instances."
    echo "                         If not specified, defaults to 10."
    echo "                -v       Be verbose."
}
fatal_usage() {
    echo "$PROG_NAME:" "$@" 1>&2
    usage
    exit 1
}
fatal() {
    echo "$PROG_NAME:" "$@" 1>&2
    exit 1
}
warning() {
    echo "[warn]" "$@" 1>&2
}
inform() {
    if [ "$VERBOSE" == "true" ]; then
        echo "[info]" "$@"
    fi
}

# verify & handle special situation
verify_aws() {
    local _aws_loc=$(which aws)
    if [ "$_aws_loc" == "" ] ; then
        fatal "aws not installed"
    fi
    if ! [ -e "$HOME/.aws/config" ] ; then
        fatal "aws not configured"
    fi
}
verify_task() {
    local _task_file="$1"
    if [ -e "$_task_file" ] ; then
        local _total_num=$(head -n 1 $_task_file | awk '{print $1}')
        local _num_of_done=$(tail -n +2 $_task_file | grep "done" | wc -l | awk '{print $1}')
        if [ "$_total_num" != "$_num_of_done" ] ; then
            fatal "found unfinished task -- $_task_file:$_num_of_done/$_total_num"
        fi
    fi
}
verify_copy_num() {
    local re='^[1-9][0-9]*$'
    if ! [[ "$1" =~ $re ]] ; then
        fatal "illegal instance count $1"
    fi
}
verify_instance() {
    local _instance_id="$1"
    local _msg="$2"
    local re='^i-[0-9a-f]+$'
    if ! [[ "$_instance_id" =~ $re ]] ; then
        fatal "$_msg"
    fi
}

# task: a description of sync job status
task_create_begin() {
    local _origin=$1
    inform "create instance from $_origin"
}
task_create_end() {
    local _remote=$1
    echo "$_remote created" >>$TASK_FILE
    echo "$_remote created"
}
task_sync_begin() {
    local _remote=$1
    local _dir="$2"
    sed -i".old" "s/$_remote created/$_remote syncing/" $TASK_FILE
    inform "$_remote syncing '$_dir'"
}
task_sync_end() {
    local _succeed=$1
    local _remote=$2
    if [ "$_succeed" == "T" ] ; then
        sed -i".old" "s/$_remote syncing/$_remote done/" $TASK_FILE
        inform "$_remote done"
    else
        inform "failed to sync $_remote"
    fi
}

util_get_host() {
    local _instance_id=$1
    local _extra_msg=$2
    local _host=$(aws ec2 describe-instances --instance-ids $_instance_id --output text --query "Reservations[*].Instances[*].PublicDnsName")
    if [ "$_host" == "" ] ; then
        fatal "can't find host of instance $_instance_id $_extra_msg"
    else
        echo $_host
    fi
}
util_get_user() {
    local _host=$1
    local _ssh_key=$2
    local _user=$(ssh -o StrictHostKeyChecking=no -i $_ssh_key root@$_host "whoami" </dev/null 2>/dev/null)
    if [ "$_user" != "root" ] ; then
        _user=$(echo $_user | sed -r 's/^[^"]*"([^"]+)".*$/\1/')
    fi
    if [ "$_user" == "" ] ; then
        fatal "failed to get user of host $_host"
    else
        echo $_user
    fi
}

# create instance & check status
do_create() {
    local _origin=$1

    # inform "create instance from $_origin."
    task_create_begin $_origin

    # BEGIN

    QUERY=`aws ec2 describe-instances --filters "Name=instance-id,Values=$_origin" --output text --query 'Reservations[*].Instances[*].{ImageId:ImageId, KeyName:KeyName, GroupId:SecurityGroups[*].GroupId, AvailabilityZone:Placement.AvailabilityZone, INSTANCE_TYPE:InstanceType}'`
    read AVAILABILITY_ZONE INSTANCE_TYPE IMAGE_ID CREDENTIAL SECURITY_GROUP <<<$(echo $QUERY)
    SECURITY_GROUP=$(echo "$SECURITY_GROUP" | cut -d ' ' -f 2)

    local _remote=`aws ec2 run-instances --image-id $IMAGE_ID --security-group-ids $SECURITY_GROUP --count 1 --placement AvailabilityZone="$AVAILABILITY_ZONE" --instance-type $INSTANCE_TYPE --key-name $CREDENTIAL --query 'Instances[0].InstanceId' | sed 's/"//g'`
    verify_instance "$_remote" "failed to create instance"

    local _host=$(util_get_host $_remote "") || exit 1
    while true; do
        inform "check if $_remote is ready..."
        local _ready=$(ssh-keyscan $_host 2>/dev/null)
        if [ "$_ready" != "" ] ; then
            break
        fi
        sleep 3
    done
    # END

    task_create_end $_remote
}

do_sync() {
    local _origin=$1
    local _remote=$2
    local _dir="$3"
    local _ssh_key=$PEM_FILE

    inform "sync: read host1"
    local _host1=$(util_get_host $_origin "(origin)") || exit 1
    inform "sync: read host2"
    local _host2=$(util_get_host $_remote "(to be sync)") || exit 1

    inform "sync: read user1"
    local _user1=$(util_get_user $_host1 $_ssh_key "(origin)") || exit 1
    inform "sync: read user2"
    local _user2=$(util_get_user $_host2 $_ssh_key "(to be sync)") || exit 1

    # inform "sync $_origin to $_remote..."

    task_sync_begin $_remote "$_dir"
    # BEGIN
    # rsync -avr --progress -e "ssh -i $_ssh_key" -d $_dir $_user@$_host:$_dir
    local _succeed="F"
    for ((i=0; i<3; i++))
    do
        inform "$_origin -> $_remote, dir:$_dir, try $i"
        inform "$_user1@$_host1 -> $_user2@$_host2 :$_dir"
        scp -o StrictHostKeyChecking=no -3 -r -i $_ssh_key $_user1@$_host1:"$_dir" $_user2@$_host2:"$_dir" 2>/dev/null
        if [ "$?" == "0" ]; then
            _succeed="T"
            break
        fi
    done
    # END

    task_sync_end $_succeed $_remote
}

main() {
    local _task_file=$TASK_FILE
    local _ssh_key=$PEM_FILE

    # TODO: create or read 'task'
    verify_task "$TASK_FILE"
    echo "$COPY_NUM $INSTANCE_ID :$COPY_DIR" >$_task_file

    local _num=$(head -n 1 $_task_file | awk '{print $1}')
    local _origin=$(head -n 1 $_task_file | awk '{print $2}')
    local _dir=$(head -n 1 $_task_file | sed 's/^.*://')

    # pre-creation verification
    local _host=$(util_get_host $_origin "(origin)") || exit 1
    if [ "$VERBOSE" == "true" ]; then
        echo "main: found host $_host"
    fi
    local _user=$(util_get_user $_host $_ssh_key "(origin)") || exit 1
    if [ "$_user" == "" ]; then exit 1; fi
    if [ "$VERBOSE" == "true" ]; then
        echo "main: found user $_user"
    fi
    local _dir_exist=$(ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user@$_host "if [ -d '$_dir' ] ; then echo T; else echo F; fi")
    if [ "$_dir_exist" == "T" ] ; then
        if [ "$VERBOSE" == "true" ]; then
            echo "main: found directory $_dir"
        fi
    else
        fatal "can't find directory '$_dir' on original instance $_origin"
    fi

    # TODO: when create failed, retry
    # create
    local _num_to_create=$(expr $_num - $(tail -n +2 $_task_file | wc -l | awk '{print $1}'))
    for ((i=0; i<_num_to_create; i++))
    do
        (do_create $_origin)
    done

    # TODO: when sync failed, retry (move retry logic here)
    # sync
    for _remote in $(tail -n +2 $_task_file | grep "created" | awk '{print $1}');
    do
        (do_sync $_origin $_remote "$_dir")
    done

    # done
    echo "All done."
}

while true ; do
    case "$1" in
        -h) usage ; exit 0 ;;
        -d) shift ; COPY_DIR="$1" ; shift ;;
        -n) shift ; COPY_NUM="$1" ; shift ;;
        -v) shift ; VERBOSE="true" ;;
        -*) fatal_usage "illegal option $1" $(usage) ;;
        *)
            if [ "$#" != "0" ] && [ "$INSTANCE_ID" != "" ] ; then
                fatal_usage "unknown options: $@"
            elif [ "$#" == "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                fatal_usage "instance not specified"
            elif [ "$#" != "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                INSTANCE_ID="$1"
                shift
            else
                verify_instance "$INSTANCE_ID" "illegal instance id $INSTANCE_ID"
                verify_copy_num "$COPY_NUM"
                verify_aws
                main
                exit 0
            fi ;;
    esac
done
