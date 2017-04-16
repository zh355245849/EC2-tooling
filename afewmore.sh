#!/bin/bash

##### script configuration #####

PROG_NAME="afewmore"
TASK_FILE="task.0"
PEM_FILE="us-east-1"
# PEM_FILE="$HOME/.ssh/us-east-1"

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
TellUser() {
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
# verify_ssh_login() {
#     local _ssh_loc=$(which ssh)
#     if [ "$_ssh_loc" == "" ] ; then
#         fatal "aws not installed"
#     fi
# }
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
    local _origin_id="$2"
    local _user="$3"
    local _host="$4"
    local _dir="$5"
    if [ "$_dir" == "" ] ; then
        fatal "directory can't be empty"
    fi
    local _dir_exist=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user@$_host "if [ -d '$_dir' ] ; then echo T; else echo F; fi")
    if [ "$_dir_exist" != "T" ] ; then
        fatal "can't find directory '$_dir' on origin instance ($_origin_id)"
    fi
}

##### Configuration #####

# task: a description of sync job status
# line 1:<total number> <instance> :<directory>
# line 2:<dup-instance-0> <status>
# line 3:<dup-instance-1> <status>
# line 4:<dup-instance-2> <status>

# All create/read/write code related to task are in this session

task_create() {
    task_verify "$TASK_FILE"
    echo "$COPY_NUM $INSTANCE_ID :$COPY_DIR" >$TASK_FILE
}
task_add() {
    local _instance="$1"
    echo "$_instance created" >>"$TASK_FILE"
}
task_change() {
    local _instance="$1"
    local _old_status="$2"
    local _new_status="$3"
    sed -i".old" "s/$_instance $_old_status/$_instance $_new_status/" "$TASK_FILE"
}
task_read_total_num() {
    echo $(head -n 1 "$TASK_FILE" | awk '{print $1}')
}
task_read_num_to_create() {
    echo $(expr $(task_read_total_num) - $(tail -n +2 $TASK_FILE | wc -l | awk '{print $1}'))
}
task_read_sync_list() {
    echo $(tail -n +2 $TASK_FILE | grep "created" | awk '{print $1}');
}
task_read_origin() {
    echo $(head -n 1 $TASK_FILE | awk '{print $2}')
}
task_read_dir() {
    # when read directory, try append '/', which will affect how 'rsync' works later
    echo $(head -n 1 $TASK_FILE | sed 's/^.*://' | sed 's/[^\/]$/&\//')
}

# 1. No unfinished task
# TODO: 2. Only one 'afewmore' is running (current one)
task_verify() {
    local _task_file="$1"
    if [ -e "$_task_file" ] ; then
        local _total_num=$(head -n 1 $_task_file | awk '{print $1}')
        local _num_of_done=$(tail -n +2 $_task_file | grep "done" | wc -l | awk '{print $1}')
        if [ "$_total_num" != "$_num_of_done" ] ; then
            fatal "found unfinished task -- $_task_file:$_num_of_done/$_total_num"
        fi
    fi
}

##### callbacks #####

when_instance_create_begin() {
    local _origin_id="$1"
    local _index="$2"
    inform "create duplicate instance $_index from origin instance ($_origin_id)"
}
when_instance_create_end() {
    local _exit_code="$1"
    local _dup_id="$2"
    local _index="$3"
    if [ "$_dup_id" != "" ] && [ "$_exit_code" == "0" ] ; then
        task_add "$_dup_id"
        inform "duplicate instance $_index ($_dup_id) created"
    else
        inform "failed to create instance $_index ($_dup_id)"
    fi
}
when_instance_sync_begin() {
    local _dup_id="$1"
    local _dir="$2"
    local _index="$3"
    task_change "$_dup_id" "created" "syncing"
    inform "syncing '$_dir' to duplicate instance $_index ($_dup_id)"
}
when_instance_sync_end() {
    local _exit_code="$1"
    local _dup_id="$2"
    local _index="$3"
    if [ "$_exit_code" == "0" ] ; then
        task_change "$_dup_id" "syncing" "done"
        inform "duplicate instance $_index done ($_dup_id)"
        TellUser "$_dup_id"
    else
        task_change "$_dup_id" "syncing" "created"
        inform "failed to sync duplicate instance $_index ($_dup_id)"
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
# TODO: better check machanism
wait_host_ready() {
    local _instance="$1"
    local _host="$2"
    local _msg="$3"
    local _timeout=300
    inform "wait for $_msg instance ($_instance) ready"
    for ((i=0;i<_timeout;i+=6))
    do
        sleep 6
        # read _inst_status _sys_status<<<$(aws ec2 describe-instance-status --instance-id $_instance --output text --query 'InstanceStatuses[0].{system:SystemStatus.Status,inst:InstanceStatus.Status}')
        # if [ "$_inst_status" != "ok" ] || [ "$_sys_status" != "ok" ] ; then
        #     continue
        # fi
        local _ret=$(ssh-keyscan $_host 2>/dev/null)
        if [ "$?" == "0" ] && [ "$_ret" != "" ] ; then
            return 0
        fi
    done
    fatal "wait timeout, instance=$_instance"
}
util_get_user() {
    local _host=$1
    local _ssh_key=$2
    local _user=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key root@$_host "whoami" 2>/dev/null)
    if [ "$_user" != "root" ] ; then
        _user=$(echo $_user | sed -r 's/^[^"]*"([^"]+)".*$/\1/')
    fi
    if [ "$_user" == "" ] ; then
        fatal "failed to get user of host $_host"
    else
        echo $_user
    fi
}

do_create() {
    local _index="$1"
    local _origin_id="$2"

    # read origin instance information
    local _query=$(aws ec2 describe-instances \
        --filters "Name=instance-id,Values=$_origin_id" \
        --output text \
        --query 'Reservations[*].Instances[*].{ImageId:ImageId,KeyName:KeyName,GroupId:SecurityGroups[*].GroupId,AvailabilityZone:Placement.AvailabilityZone,InstanceType:InstanceType}')
    read _avail_zone _img_id _inst_type _key_name _group_ids<<<$(echo "$_query")
    _group_ids=$(echo "$_group_ids" | sed 's/GROUPID //g')
    # echo 1>&2 $_avail_zone $_inst_type $_img_id $_key_name $_group_ids
    # exit 1

    # create duplicate instance [i]
    local _dup_id=$(aws ec2 run-instances \
        --image-id "$_img_id" \
        --security-group-ids $_group_ids \
        --count 1 \
        --placement AvailabilityZone="$_avail_zone" \
        --instance-type "$_inst_type" \
        --key-name "$_key_name" \
        --query 'Instances[0].InstanceId')
    if [ "$?" != "0" ] ; then
        exit 1
    fi
    _dup_id=$(echo "$_dup_id" | sed 's/"//g')

    # return duplicate instance id
    echo "$_dup_id"

    exit 0
}

do_sync() {
    local _index="$1"
    local _origin_id="$2"
    local _dup_id="$3"
    local _dir="$4"
    local _ssh_key=$PEM_FILE

    local _host1=$(util_get_host $_origin_id "(origin)")
    if [ "$_host1" == "" ]; then exit 1; fi
    local _host2=$(util_get_host $_dup_id "(duplicate $_index)")
    if [ "$_host2" == "" ]; then exit 1; fi

    wait_host_ready "$_origin_id" "$_host1" "origin"
    wait_host_ready "$_dup_id" "$_host2" "duplicate $_index"

    local _user1=$(util_get_user $_host1 $_ssh_key "(origin)")
    if [ "$_user1" == "" ]; then exit 1; fi
    local _user2=$(util_get_user $_host2 $_ssh_key "(duplicate $_index)")
    if [ "$_user2" == "" ]; then exit 1; fi

    for ((i=0; i<1; i++))
    do
        inform "$_origin_id -> $_dup_id, dir:$_dir, try $i"
        inform "$_user1@$_host1 -> $_user2@$_host2 :$_dir"

        local _has_rsync=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'which rsync')
        if [ "$_has_rsync" != "" ] ; then
            # generate temporary SSH key
            local _tmp_key=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'if [ -e ".ssh/afewmore_tmp.rsa" ]; then echo T; fi')
            if [ "$_tmp_key" == "" ]; then
                ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'ssh-keygen -q -t rsa -f ./.ssh/afewmore_tmp.rsa'
            fi
            local _tmp_pubkey=`ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 'cat /$HOME/.ssh/afewmore_tmp.rsa.pub'`
            ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user2@$_host2 "echo $_tmp_pubkey >> ./.ssh/authorized_keys"
            ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user1@$_host1 "rsync -q -avr --progress -e 'ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i .ssh/afewmore_tmp.rsa' -d $_dir $_user2@$_host2:$_dir 2>/dev/null"
            if [ "$?" == "0" ]; then
                exit 0
            fi
        else
            warning "origin instance ($_origin_id) doesn't support 'rsync'"
            ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i $_ssh_key $_user2@$_host2 "mkdir -p '$_dir'"
            echo scp -o BatchMode=yes -o StrictHostKeyChecking=no -3 -r -i $_ssh_key "'$_user1@$_host1:${_dir}.*'" "'$_user2@$_host2:$_dir'" | sh
            exit 0
            # if [ "$?" == "0" ]; then
            #     exit 0
            # fi
        fi
    done

    exit 1
}

# TODO: fix index
main() {
    local _ssh_key=$PEM_FILE

    task_create
    local _origin_id=$(task_read_origin)
    local _dir=$(task_read_dir)

    # pre-creation verification
    local _host=$(util_get_host $_origin_id "(origin)")
    if [ "$_host" == "" ]; then exit 1; fi
    wait_host_ready "$_origin_id" "$_host" "origin"
    local _user=$(util_get_user $_host $_ssh_key "(origin)")
    if [ "$_user" == "" ]; then exit 1; fi
    verify_copy_dir "$_ssh_key" "$_origin_id" "$_user" "$_host" "$_dir"

    # create
    local _num_to_create=$(task_read_num_to_create)
    for ((i=0; i<_num_to_create; i++))
    do
        when_instance_create_begin "$_origin_id" "$i"
        local _rem=$(do_create "$i" "$_origin_id")
        when_instance_create_end "$?" "$_rem" "$i"
    done

    # sync
    local _index=0
    for _dup_id in $(task_read_sync_list);
    do
        when_instance_sync_begin "$_dup_id" "$_dir" "$_index"
        (do_sync "$_index" "$_origin_id" "$_dup_id" "$_dir")
        when_instance_sync_end "$?" "$_dup_id" "$_index"
        _index=$(expr $_index + 1)
    done

    # done
    TellUser "All done."
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
