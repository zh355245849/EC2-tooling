#!/bin/sh

PROG_NAME="afewmore"
TASK_FILE="task.0"

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
fatal() {
    echo "$PROG_NAME:" "$@" 1>&2
    usage
    exit 1
}

# verify & handle special situation
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
verify_copy_dir() {
    if ! [ -d "$1" ]; then
        fatal "$1: No such directory"
    fi
}
verify_instance() {
    local re='^i-[0-9a-f]{10}$'
    if ! [[ "$1" =~ $re ]] ; then
        fatal "illegal instance id $1"
    fi
}

# task: a description of sync job status
task_show() {
    local _task_file=$TASK_FILE

    local _origin=$(head -n 1 $_task_file | awk '{print $2}')
    local _total_num=$(head -n 1 $_task_file | awk '{print $1}')

    local _num_of_created=$(tail -n +2 $_task_file | wc -l | awk '{print $1}')
    local _num_of_syncing=$(tail -n +2 $_task_file | grep "syncing" | wc -l | awk '{print $1}')
    local _num_of_done=$(tail -n +2 $_task_file | grep "done" | wc -l | awk '{print $1}')

    local _num_to_create=$(expr $_total_num - $_num_of_created)
    local _num_to_sync=$(tail -n +2 $_task_file | grep "created" | wc -l | awk '{print $1}')

    echo $_task_file
    echo $_origin
    echo Progress: $(expr $_num_to_create + $_num_to_sync + $_num_of_syncing)/$_total_num
    echo To Create: $_num_to_create
    echo To Sync: $_num_to_sync
    echo Syncing: $_num_of_syncing
}
task_create_begin() {
    local _origin=$1
    # echo "info: create instance from $_origin"
}
task_create_end() {
    local _remote=$1
    echo "$_remote created" >>$TASK_FILE
    echo "info: $_remote created"
}
task_sync_begin() {
    local _remote=$1
    local _dir="$2"
    sed -i ".old" "s/$_remote created/$_remote syncing/" $TASK_FILE
    echo "info: $_remote syncing '$_dir'"
}
task_sync_end() {
    local _remote=$1
    sed -i ".old" "s/$_remote syncing/$_remote done/" $TASK_FILE
    echo "info: $_remote done"
}

do_create() {
    local _origin=$1
    local _remote="i-0000000001"

    # echo "info: create instance from $_origin."
    task_create_begin $_origin

    # BEGIN
    # IMAGE_ID=`aws ec2 describe-instances --instance-ids $_origin --query Reservations[].Instances[].ImageId | sed 's/\"//g' | grep [[:alnum:]]`
    # CREDENTIAL=`aws ec2 describe-instances --instance-ids $_origin --query Reservations[].Instances[].KeyName | sed 's/\"//g' | grep "[[:alnum:]]"`
    # SECURITU_GROUP=`aws ec2 describe-instances --instance-ids $_origin --query Reservations[].Instances[].SecurityGroups[].GroupId | sed 's/\"//g' | grep "[[:alnum:]]"`
    # AVAILABILITY_ZONE=`aws ec2 describe-instances --instance-ids $_origin --query Reservations[].Instances[].Placement.AvailabilityZone | sed 's/\"//g' | grep "[[:alnum:]]"`
    # INSTANCE_TYPE=`aws ec2 describe-instances --instance-ids $_origin --query Reservations[].Instances[].InstanceType | sed 's/\"//g' | grep "[[:alnum:]]"`

    # aws ec2 run-instances --image-id $IMAGE_ID --security-group-ids $SECURITU_GROUP --count 1 --placement AvailabilityZone="$AVAILABILITY_ZONE" --instance-type $INSTANCE_TYPE --key-name $CREDENTIAL
    # END

    task_create_end $_remote
}

# util_get_user() { LOGIN_USER="root" }
# util_get_host() { LOGIN_HOST="" }
do_sync() {
    local _origin=$1
    local _remote=$2
    local _dir="$3"
    local _ssh_key=""
    local _user=""
    local _host=""

    # echo "info: sync $_origin to $_remote..."
    task_sync_begin $_remote "$_dir"
    # rsync -avr --progress -e "ssh -i $_ssh_key" -d $_dir $_user@$_host:$_dir
    task_sync_end $_remote
}

main() {
    local _task_file=$TASK_FILE

    # create 'task'
    echo "$COPY_NUM $INSTANCE_ID :$COPY_DIR" >$_task_file

    # create
    local _origin=$(head -n 1 $_task_file | awk '{print $2}')
    local _num_to_create=$(expr $(head -n 1 $_task_file | awk '{print $1}') - $(tail -n +2 $_task_file | wc -l | awk '{print $1}'))
    for ((i=0; i<_num_to_create; i++))
    do
        (do_create $_origin)
    done

    # sync
    local _dir=$(head -n 1 $_task_file | sed 's/^.*://')
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
        -*) fatal "illegal option $1" ;;
        *)
            if [ "$#" != "0" ] && [ "$INSTANCE_ID" != "" ] ; then
                fatal "unknown options: $@"
            elif [ "$#" == "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                fatal "instance not specified"
            elif [ "$#" != "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                INSTANCE_ID="$1"
                shift
            else
                verify_task "$TASK_FILE"
                verify_copy_dir "$COPY_DIR"
                verify_copy_num "$COPY_NUM"
                verify_instance "$INSTANCE_ID"
                main
                exit 0
            fi ;;
    esac
done
