usage_for_tool() {
    echo "The afewmore tool can be used to duplicate a given EC2 instance.  When doing so, it creates multiple new instances and populates their data directory by copying the data from the original.
    Arguments options:
    -d dir   Copy the contents of this data directory from the orignal source
	      instance to all the new instances.  If not specified, defaults
	      to /data.
    -h       Print a usage statement and exit.

    -n num   Create this many new instances.  If not specified, defaults to
	      10.

    -v       Be verbose."
    exit 0
}

option="${1}"
case ${option} in
   -h) usage_for_tool
      ;;
   -n) "source copyInstance"
      ;;
   -d) "source backup";;
   -v) "source verbose";;
   -*) "This argument is not support ${option}"
      ;;
   *) 
      echo "`basename ${0}`:usage: [-h usage]"
      ;;
esac


