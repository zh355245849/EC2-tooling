#!/bin/bash

##### script configuration #####

PROG_NAME=$(basename "$0")
CONFIG_DIR="$HOME/.afewmore"

TASK_FILE="$CONFIG_DIR/task.0"

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
    echo 1>&2 "$PROG_NAME:" "$@"
    exit 1
}
warning() {
    echo 1>&2 "[warn]" "$@"
}
inform() {
    if [ "$VERBOSE" == "T" ] ; then
        echo "[info]" "$@"
    fi
}
yes_or_no() {
    local _prompt_msg="$@"
    read -p "${_prompt_msg}[y/n]" -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]] ; then
        return 0
    else
        return 1
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
verify_ssh() {
    local _origin_id="$1"
    local _ssh_loc=$(which ssh)
    if [ "$_ssh_loc" == "" ] ; then
        fatal "ssh not installed"
    fi
    local _host=$(util_get_host $_origin_id "(origin)")
    if [ "$_host" == "" ]; then exit 1; fi
    local _user=$(util_get_user $_host "(origin)")
    if [ "$_user" == "" ]; then exit 1; fi
    local _login_test=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user@$_host "echo Y" 2>/dev/null)
    if [ "$_login_test" != "Y" ] ; then
        fatal "ssh not properly configured"
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
    local re='^i-[0-9a-f]+$'
    if ! [[ "$_instance_id" =~ $re ]] ; then
        fatal "illegal instance id $_instance_id"
    fi
}
verify_copy_dir() {
    local _origin_id="$1"
    local _dir="$2"

    if [ "$_dir" == "" ] ; then
        fatal "directory can't be empty"
    fi
    if [ "$_dir" == "/" ] ; then
        fatal "sync root directory '/' is not supported"
    fi

    # check if origin instance has directory
    local _host=$(util_get_host $_origin_id "(origin)")
    if [ "$_host" == "" ]; then exit 1; fi
    (do_check_ready "$_origin_id" "(origin)")
    if [ "$?" != "0" ]; then exit 1; fi
    local _user=$(util_get_user $_host "(origin)")
    if [ "$_user" == "" ]; then exit 1; fi
    local _dir_exist=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user@$_host "if [ -d '$_dir' ] ; then echo T; else echo F; fi")
    if [ "$_dir_exist" != "T" ] ; then
        fatal "can't find directory '$_dir' on instance $_origin_id (origin)"
    fi
}

##### Configuration #####

# task: a description of sync job status
# line 1:<total number> <instance> :<directory>
# line 2:<dup-instance-0> <status>
# line 3:<dup-instance-1> <status>
# line 4:<dup-instance-2> <status>

# All create/read/write code related to task are in this session

lock() {
    flock -x 202 || exit 1
}
unlock() {
    flock -u 202 || exit 1
}

task_create() {
    if ! [ -e "$TASK_FILE" ] ; then
        echo "$COPY_NUM $INSTANCE_ID :$COPY_DIR" >$TASK_FILE
    else
        lock
        local _total_num=$(head -n 1 $TASK_FILE | awk '{print $1}')
        local _num_of_done=$(tail -n +2 $TASK_FILE | grep "done" | wc -l | awk '{print $1}')
        unlock
        if [ "$_total_num" != "$_num_of_done" ] ; then
            yes_or_no "found unfinished task $TASK_FILE ($_num_of_done/$_total_num), continue it?" \
                && lock \
                && sed -i".old" -r 's/(i.*) syncing/\1 ready/' "$TASK_FILE" \
                && unlock \
                && return 0
            yes_or_no "found unfinished task $TASK_FILE ($_num_of_done/$_total_num), delete it?" || exit 0
        fi
        lock
        echo "$COPY_NUM $INSTANCE_ID :$COPY_DIR" >$TASK_FILE
        unlock
    fi
}
task_add() {
    local _instance="$1"
    local _status="$2"
    lock
    echo "$_instance $_status" >>"$TASK_FILE"
    unlock
}
task_change() {
    local _instance="$1"
    local _old_status="$2"
    local _new_status="$3"
    lock
    sed -i".old" "s/$_instance $_old_status/$_instance $_new_status/" "$TASK_FILE"
    unlock
}
task_find() {
    local _status="$1"
    lock
    echo $(tail -n +2 $TASK_FILE | grep "$_status" | awk '{print $1}')
    unlock
}
task_count() {
    local _status="$1"
    lock
    echo $(tail -n +2 $TASK_FILE | grep "$_status" | wc -l | awk '{print $1}')
    unlock
}
task_read_origin() {
    lock
    echo $(head -n 1 $TASK_FILE | awk '{print $2}')
    unlock
}
task_read_dir() {
    lock
    # when read directory, try append '/', which will affect how 'rsync' works later
    echo $(head -n 1 $TASK_FILE | sed 's/^.*://' | sed 's/[^\/]$/&\//')
    unlock
}
task_read_total_num() {
    lock
    echo $(head -n 1 "$TASK_FILE" | awk '{print $1}')
    unlock
}
task_done() {
    local _todo=$(expr $(task_read_total_num) - $(task_count "done"))
    if [[ $_todo == 0 ]] ; then
        echo "T"
    else
        echo "F"
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
        task_add "$_dup_id" "created"
        inform "duplicate instance $_index created ($_dup_id)"
    else
        inform "failed to create instance $_index ($_dup_id)"
    fi
}
when_instance_ready_begin() {
    local _dup_id="$1"
    local _index="$2"
    inform "wait for duplicate instance $_index ready ($_dup_id)"
}
when_instance_ready_end() {
    local _exit_code="$1"
    local _dup_id="$2"
    local _index="$3"
    if [ "$_dup_id" != "" ] && [ "$_exit_code" == "0" ] ; then
        task_change "$_dup_id" "created" "ready"
        inform "duplicate instance $_index ready to be sync ($_dup_id)"
    else
        inform "failed to connect duplicate instance $_index, try reboot ($_dup_id)"
        # send reboot command
        (aws ec2 reboot-instances --instance-ids "$_dup_id"  1>/dev/null 2>/dev/null)
    fi
}
when_instance_sync_begin() {
    local _dup_id="$1"
    local _dir="$2"
    local _index="$3"
    task_change "$_dup_id" "ready" "syncing"
    inform "syncing '$_dir' to duplicate instance $_index ($_dup_id)"
}
when_instance_sync_end() {
    local _exit_code="$1"
    local _dup_id="$2"
    local _index="$3"
    if [ "$_exit_code" == "0" ] ; then
        inform "duplicate instance $_index finished sync ($_dup_id)"
    else
        task_change "$_dup_id" "syncing" "ready"
        inform "failed to sync duplicate instance $_index ($_dup_id)"
    fi
}
when_instance_done_begin() {
    local _dup_id="$1"
    local _index="$2"
    inform "check sync result of duplicate instance $_index ($_dup_id)"
}
when_instance_done_end() {
    local _exit_code="$1"
    local _dup_id="$2"
    local _index="$3"
    if [ "$_exit_code" == "0" ] ; then
        task_change "$_dup_id" "syncing" "done"
        inform "duplicate instance $_index done ($_dup_id)"
        TellUser "$_dup_id"
    else
        task_change "$_dup_id" "syncing" "ready"
        inform "failed to sync duplicate instance $_index ($_dup_id)"
    fi
}

##### Main Routines #####

util_get_host() {
    local _instance_id="$1"
    local _extra_msg="$2"
    local _host=$(aws ec2 describe-instances --instance-ids $_instance_id --output text --query "Reservations[*].Instances[*].PublicDnsName")
    if [ "$_host" == "" ] ; then
        fatal "can't find host of instance $_instance_id $_extra_msg"
    else
        echo $_host
    fi
}
util_get_user() {
    local _host="$1"
    local _extra_msg="$2"
    local _user=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@$_host "whoami" 2>/dev/null)
    if [ "$_user" != "root" ] ; then
        _user=$(echo $_user | sed -r 's/^[^"]*"([^"]+)".*$/\1/')
    fi
    if [ "$_user" == "" ] ; then
        fatal "failed to get user of host $_host $_extra_msg"
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

# TODO: improve 'ready' check (add aws instance status check)
do_check_ready() {
    local _instance="$1"
    local _msg="$2"

    local _host=$(util_get_host "$_instance" "$_msg")
    if [ "$_host" == "" ]; then exit 1; fi

    local _timeout=300
    for ((i=0;i<_timeout;i+=6))
    do
        local _ret=$(ssh-keyscan $_host 2>/dev/null)
        if [ "$?" == "0" ] && [ "$_ret" != "" ] ; then
            exit 0
        fi
        sleep 6
    done
    fatal "wait instance $_instance timeout $_msg"
}

do_sync() {
    local _index="$1"
    local _origin_id="$2"
    local _dup_id="$3"
    local _dir="$4"

    local _host1=$(util_get_host $_origin_id "(origin)")
    if [ "$_host1" == "" ]; then exit 1; fi
    local _host2=$(util_get_host $_dup_id "(duplicate $_index)")
    if [ "$_host2" == "" ]; then exit 1; fi

    local _user1=$(util_get_user $_host1 "(origin)")
    if [ "$_user1" == "" ]; then exit 1; fi
    local _user2=$(util_get_user $_host2 "(duplicate $_index)")
    if [ "$_user2" == "" ]; then exit 1; fi

    inform "$_user1@$_host1 -> $_user2@$_host2 :$_dir"

    # ensure permission on directory
    if [ "$_user1" != "root" ] ; then
        local _chown1=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 "which chown" 2>/dev/null)
        if [ "$_chown1" == "" ]; then
            fatal "'chown' not found on origin instance ($_origin_id)"
        fi
        local _sudo1=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 "which sudo" 2>/dev/null)
        (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 "$_sudo1 chown -R $_user1 '$_dir'")
        if [ "$?" != "0" ]; then
            fatal "failed to chown directory '$_dir' on origin instance ($_origin_id)"
        fi
    fi
    if [ "$_user2" != "root" ] ; then
        local _sudo2=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "which sudo" 2>/dev/null)
        (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "$_sudo2 mkdir -p '$_dir'")
        if [ "$?" != "0" ]; then
            fatal "failed to create directory '$_dir' on duplicate instance $_index ($_dup_id)"
        fi
        local _chown2=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "which chown" 2>/dev/null)
        if [ "$_chown2" == "" ]; then
            fatal "'chown' not found on duplicate instance $_index ($_origin_id)"
        fi
        (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "$_sudo2 chown -R $_user2 '$_dir'")
        if [ "$?" != "0" ]; then
            fatal "failed to chown directory '$_dir' on duplicate instance $_index ($_dup_id)"
        fi
    fi

    # try 'rsync' first
    local _has_rsync=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 'which rsync 2>&1 1>/dev/null && echo Y || echo N' 2>/dev/null)
    if [ "$_has_rsync" == "Y" ] ; then
        # generate temporary SSH key on origin instance
        local _tmp_key=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 'if [ -e ".ssh/afewmore_tmp.rsa" ]; then echo T; fi' 2>/dev/null)
        if [ "$_tmp_key" == "" ]; then
            (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 'ssh-keygen -N "" -q -t rsa -f ./.ssh/afewmore_tmp.rsa' 1>/dev/null 2>/dev/null)
            if [ "$?" != "0" ]; then
                fatal "failed to create temporary ssh-key on origin instance ($_origin_id)"
            fi
        fi
        # get temporary SSH public key
        local _tmp_pubkey=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 'cat /$HOME/.ssh/afewmore_tmp.rsa.pub' 2>/dev/null)
        if [ "$?" != "0" ]; then
            fatal "failed to get public key from origin instance ($_origin_id)"
        fi
        # copy temporary SSH public key to duplicate instance
        (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "echo $_tmp_pubkey >> ./.ssh/authorized_keys" 1>/dev/null 2>/dev/null)
        if [ "$?" != "0" ]; then
            fatal "failed to copy public key to duplicate instance $_index ($_dup_id)"
        fi
        # run rsync on orign instance
        (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user1@$_host1 "rsync -q -avr -e 'ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i .ssh/afewmore_tmp.rsa' -d $_dir $_user2@$_host2:$_dir 2>/dev/null" 1>/dev/null 2>/dev/null)
        if [ "$?" != "0" ]; then
            fatal "rsync failed to copy '$_dir' to duplicate instance $_index ($_dup_id)"
        fi
        exit 0
    fi

    # try 'scp'
    # copy to /tmp
    local _tmp_dir="/tmp$_dir"
    (scp -o BatchMode=yes -o StrictHostKeyChecking=no -3 -r "$_user1@$_host1:$_dir" "$_user2@$_host2:$_tmp_dir")
    if [ "$?" != "0" ]; then exit 1; fi
    # clean dest directory
    (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "rm -rf \$(find '$_dir' 2>/dev/null | tail -n +2)")
    if [ "$?" != "0" ]; then
        fatal "failed to clean directory '$_dir' on duplicate instance $_index ($_dup_id)"
    fi
    # move from /tmp to dest directory
    (ssh -o BatchMode=yes -o StrictHostKeyChecking=no $_user2@$_host2 "mv -f '$_tmp_dir' '$(dirname $_dir)'")
    if [ "$?" != "0" ]; then
        fatal "failed to move directory '$_dir' on duplicate instance $_index ($_dup_id)"
    fi
    exit 0
}

# TODO: better result check algorithm (e.g. checksum)
do_check_done() {
    local _origin_id="$1"
    local _dup_id="$2"
    local _dir="$3"

    # local _host1=$(util_get_host $_origin_id "(origin)")
    # if [ "$_host1" == "" ]; then exit 1; fi
    # local _host2=$(util_get_host $_dup_id "(duplicate $_index)")
    # if [ "$_host2" == "" ]; then exit 1; fi

    # local _user1=$(util_get_user $_host1 "(origin)")
    # if [ "$_user1" == "" ]; then exit 1; fi
    # local _user2=$(util_get_user $_host2 "(duplicate $_index)")
    # if [ "$_user2" == "" ]; then exit 1; fi

    exit 0
}

# TODO: fix index
main() {
    # verification (must do in order)
    inform "verifying parameters and environment..."
    verify_instance "$INSTANCE_ID"
    verify_copy_num "$COPY_NUM"
    verify_aws
    verify_ssh "$INSTANCE_ID"
    verify_copy_dir "$INSTANCE_ID" "$COPY_DIR"

    # create task file
    inform "creating task..."
    task_create
    local _origin_id=$(task_read_origin)
    local _dir=$(task_read_dir)

    # main loop
    inform "Start main loop."
    # if we didn't make any progress in 3 loops, stop trying and exit
    local _try=3
    while [ $(task_done) != "T" ] ;
    do
        local _progress=0
        local _exit_code=0

        # -> created
        local _num_to_create=$(expr $(task_read_total_num) - $(task_count ""))
        for ((i=0; i<_num_to_create; i++))
        do
            when_instance_create_begin "$_origin_id" "$i"
            local _dup_id=$(do_create "$i" "$_origin_id")
            _exit_code="$?"
            if [[ $_exit_code == 0 ]] ; then _progress=$(expr $_progress + 1); fi
            when_instance_create_end "$_exit_code" "$_dup_id" "$i"
        done

        # created -> ready
        local _index=0
        for _dup_id in $(task_find "created");
        do
            when_instance_ready_begin "$_dup_id" "$_index"
            (do_check_ready "$_dup_id" "(duplicate $_index)")
            _exit_code="$?"
            if [[ $_exit_code == 0 ]] ; then _progress=$(expr $_progress + 1); fi
            when_instance_ready_end "$_exit_code" "$_dup_id" "$_index"
            _index=$(expr $_index + 1)
        done

        # ready -> syncing
        _index=0
        for _dup_id in $(task_find "ready");
        do
            # sync
            when_instance_sync_begin "$_dup_id" "$_dir" "$_index"
            (do_sync "$_index" "$_origin_id" "$_dup_id" "$_dir")
            _exit_code="$?"
            if [[ $_exit_code == 0 ]] ; then _progress=$(expr $_progress + 1); fi
            when_instance_sync_end "$_exit_code" "$_dup_id" "$_index"
            _index=$(expr $_index + 1)
        done

        # syncing -> done
        _index=0
        for _dup_id in $(task_find "syncing");
        do
            # check done
            when_instance_done_begin "$_dup_id" "$_index"
            (do_check_done "$_origin_id" "$_dup_id" "$_dir")
            _exit_code="$?"
            if [[ $_exit_code == 0 ]] ; then _progress=$(expr $_progress + 1); fi
            when_instance_done_end "$_exit_code" "$_dup_id" "$_index"
            _index=$(expr $_index + 1)
        done

        inform '---- all:' $(task_read_total_num) 'done:' $(task_count 'done') '----'
        if [[ $_progress == 0 ]] ; then
            if [[ $_try > 0 ]] ; then
                _try=$(expr $_try - 1)
            else
                fatal 'Failed too many times,' $(task_count '') 'instances created,' $(task_count 'done') 'instances finished syncing.'
            fi
        fi
    done
    inform "All done."
}

##### option parsing & verification #####

# Create config directory
mkdir -p "$CONFIG_DIR"

# Make sure only one 'afewmore' is running.
eval "exec 200>${CONFIG_DIR}/${PROG_NAME}.lock"
flock -n 200 || fatal "another '$PROG_NAME' is running"

# For lock()/unlock()
eval "exec 202>${TASK_FILE}.lock" || fatal "failed to create task lock file ${TASK_FILE}.lock"

# Parse options, execute main().
while true ; do
    case "$1" in
        -h) usage ;;
        -d) shift ;
            if [ "${1::1}" == "/" ]; then
                COPY_DIR="$1"
            else
                COPY_DIR="$PWD/$1"
            fi;
            shift ;;
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
                main
                exit 0
            fi ;;
    esac
done
