#!/bin/bash

##### script configuration #####

PROG_NAME="afewmore"
TASK_FILE="task.0"
PEM_FILE="$HOME/devenv-key.pem"

COPY_NUM=1
COPY_DIR="/data"
INSTANCE_ID=""
VERBOSE="T"

##### helper functions #####

usage() {
    local _err_msg="$@"
    if [ "$_err_msg" != "" ] ; then
        echo 1>&2 "$PROG_NAME: $_err_msg"
    fi
    echo 1>&2 "usage: $PROG_NAME [-hv] [-d dir] [-n num] instance"
    echo 1>&2 "                -d dir   Copy the contents of this data directory from the"
    echo 1>&2 "                         orignal source instance to all the new instances."
    echo 1>&2 "                         If not specified, defaults to \"/data\"."
    echo 1>&2 "                -h       Print a usage statement and exit."
    echo 1>&2 "                -n num   Create this many new instances."
    echo 1>&2 "                         If not specified, defaults to 10."
    echo 1>&2 "                -v       Be verbose."
    if [ "$_err_msg" != "" ] ; then
        exit 1
    else
        exit 0
    fi
}
fatal() {
    echo "$PROG_NAME:" "$@" 1>&2
    exit 1
}
warning() {
    echo "[warn]" "$@" 1>&2
}
inform() {
    if [ "$VERBOSE" == "T" ] ; then
        echo "[info]" "$@"
    fi
}
# information shows to user when everything goes smoothly
stdinfo() {
    echo "$@"
}

###### Verification #####

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
verify_copy_dir() {
    local _ssh_key="$1"
    local _user="$2"
    local _host="$3"
    local _dir="$4"
    local _dir_exist=$(ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user@$_host "if [ -d '$_dir' ] ; then echo T; else echo F; fi")
    if [ "$_dir_exist" != "T" ] ; then
        fatal "can't find directory '$_dir' on origin instance $_origin"
    fi
}

##### Configuration #####

# task: a description of sync job status
task_create_begin() {
    local _origin="$1"
    local _index="$2"
    inform "create duplicate instance $_index from origin instance ($_origin)"
}
task_create_end() {
    local _remote="$1"
    echo "$_remote created" >>$TASK_FILE
    inform "$_remote created"
}
task_sync_begin() {
    local _remote="$1"
    local _dir="$2"
    sed -i".old" "s/$_remote created/$_remote syncing/" $TASK_FILE
    inform "$_remote syncing '$_dir'"
}
task_sync_end() {
    local _exit_code="$1"
    local _remote="$2"
    if [ "$_exit_code" == "0" ] ; then
        sed -i".old" "s/$_remote syncing/$_remote done/" $TASK_FILE
        inform "$_remote done"
        stdinfo "$_remote"
    else
        inform "failed to sync $_remote"
    fi
}

##### Main Routines #####

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
wait_host_ready() {
    local _host="$1"
    local _msg="$2"
    local _timeout=60
    if [ "$_msg" != "" ] ; then
        inform "$_msg"
    fi
    for ((i=0;i<_timeout;i+=3))
    do
        sleep 3
        local _ret=$(ssh-keyscan $_host 2>/dev/null)
        if [ "$?" == "0" ] && [ "$_ret" != "" ] ; then
            break
        fi
    done
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
    local _index="$1"
    local _origin="$2"

    # read origin instance information
    QUERY=$(aws ec2 describe-instances --filters "Name=instance-id,Values=$_origin" --output text --query 'Reservations[*].Instances[*].{ImageId:ImageId, KeyName:KeyName, GroupId:SecurityGroups[*].GroupId, AvailabilityZone:Placement.AvailabilityZone, INSTANCE_TYPE:InstanceType}')
    read AVAILABILITY_ZONE INSTANCE_TYPE IMAGE_ID CREDENTIAL SECURITY_GROUP <<<$(echo $QUERY)
    SECURITY_GROUP=$(echo "$SECURITY_GROUP" | cut -d ' ' -f 2)

    # create duplicate instance [i]
    local _remote=$(aws ec2 run-instances --image-id $IMAGE_ID --security-group-ids $SECURITY_GROUP --count 1 --placement AvailabilityZone="$AVAILABILITY_ZONE" --instance-type $INSTANCE_TYPE --key-name $CREDENTIAL --query 'Instances[0].InstanceId' | sed 's/"//g')
    verify_instance "$_remote" "failed to create instance $_index"

    ## inform "check if instance $_index($_remote) is ready..."
    # moved to do_sync
    echo "$_remote"

    exit 0
}

do_sync() {
    local _index="$1"
    local _origin="$2"
    local _remote="$3"
    local _dir="$4"
    local _ssh_key=$PEM_FILE

    local _host1=$(util_get_host $_origin "(origin)") || exit 1
    local _host2=$(util_get_host $_remote "(duplicate $_index)") || exit 1

    wait_host_ready "$_host1" "wait for origin instance ($_origin) ready"
    wait_host_ready "$_host2" "wait for duplicate instance $_index ($_remote) ready"

    local _user1=$(util_get_user $_host1 $_ssh_key "(origin)") || exit 1
    local _user2=$(util_get_user $_host2 $_ssh_key "(duplicate $_index)") || exit 1

    for ((i=0; i<3; i++))
    do
        inform "$_origin -> $_remote, dir:$_dir, try $i"
        inform "$_user1@$_host1 -> $_user2@$_host2 :$_dir"
        local _tmp_key=$(ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'if [ -e ".ssh/file.rsa" ]; then echo T; fi')
        if [ "$_tmp_key" == "" ]; then
            ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'ssh-keygen -q -t rsa -f ./.ssh/file.rsa'
        fi
        file=`ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'cat /$HOME/.ssh/file.rsa.pub'`
        ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user2@$_host2 "echo $file >> ./.ssh/authorized_keys"
        ssh -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 "rsync -q -avr --progress -e 'ssh -o StrictHostKeyChecking=no -i .ssh/file.rsa' -d $_dir/ $_user2@$_host2:$_dir/ 2>/dev/null"
        if [ "$?" == "0" ]; then
            exit 0
        fi
    done
    exit 1
}

# TODO: fix index
# TODO: when sync failed, retry (move retry logic here)
main() {
    local _task_file=$TASK_FILE
    local _ssh_key=$PEM_FILE

    # TODO: create or read 'task'
    verify_task "$TASK_FILE"
    echo "$COPY_NUM $INSTANCE_ID :$COPY_DIR" >$_task_file
    # parse task file
    local _num=$(head -n 1 $_task_file | awk '{print $1}')
    local _origin=$(head -n 1 $_task_file | awk '{print $2}')
    local _dir=$(head -n 1 $_task_file | sed 's/^.*://')

    # pre-creation verification
    local _host=$(util_get_host $_origin "(origin)") || exit 1
    wait_host_ready "$_host" "wait for origin instance ($_origin) ready"
    local _user=$(util_get_user $_host $_ssh_key "(origin)") || exit 1
    verify_copy_dir "$_ssh_key" "$_user" "$_host" "$_dir"

    # create
    local _num_to_create=$(expr $_num - $(tail -n +2 $_task_file | wc -l | awk '{print $1}'))
    for ((i=0; i<_num_to_create; i++))
    do
        task_create_begin "$_origin" "$i"
        local _rem=$(do_create "$i" "$_origin")
        task_create_end "$_rem"
    done

    # sync
    local _index=0
    for _remote in $(tail -n +2 $_task_file | grep "created" | awk '{print $1}');
    do
        task_sync_begin "$_remote" "$_dir"
        (do_sync "$_index" "$_origin" "$_remote" "$_dir")
        task_sync_end "$?" "$_remote"
        _index=$(expr $_index + 1)
    done

    # done
    stdinfo "All done."
}

##### option parsing & verification #####

while true ; do
    case "$1" in
        -h) usage ;;
        -d) shift ; COPY_DIR="$1" ; shift ;;
        -n) shift ; COPY_NUM="$1" ; shift ;;
        -v) shift ; VERBOSE="T" ;;
        -*) usage "illegal option $1" ;;
        *)
            if [ "$#" != "0" ] && [ "$INSTANCE_ID" != "" ] ; then
                usage "unknown options: $@"
            elif [ "$#" == "0" ] && [ "$INSTANCE_ID" == "" ] ; then
                usage "instance not specified"
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
