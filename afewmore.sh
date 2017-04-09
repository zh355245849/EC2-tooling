#!/bin/env sh

PROG_NAME="$0"
COPY_NUM=10
COPY_DIR="/data"
INSTANCE_ID=""
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

while true ; do
    case "$1" in
        -h) usage ; exit 0 ;;
        -d) shift ; COPY_DIR=$1 ; shift ;;
        -n) shift ; COPY_NUM=$1 ; shift ;;
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

