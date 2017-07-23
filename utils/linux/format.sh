#!/bin/bash

# vim: set ts=4 sts=4 sw=4 expandtab
#
# Description:
# This script is created for lamers, to simplify thier life
# 
## END DESCRIPTION
#

trap ':' INT QUIT TERM PIPE HUP

## Standart Functions 

function usage {
	cat <<-END >&2
		$0 [-t fs_type] [-m mountpoint] [-d /dev/device_name]
	--------------------------------------------------------------------------------	
		-t - filesystem type, e.g: xfs, ext4, ext3
		-m - mountpoint, e.g: /data1
		-d - device, e.g: /dev/sdc

	END
	
	exit
}

function warn {
	if ! eval "$@"; then
		echo >&2 "WARNING: command failed \"$@\""
	fi
}

function end {
	# disable tracing
	echo 2>/dev/null
	echo "Exit ..." 2>/dev/null

	(( wroteflock )) && warn "rm $lock"
}

function die {
	echo >&2 "$@"
	exit 1
}

function edie {
	# die with a quiet end()
	echo >&2 "$@"
	exec >/dev/null 2>&1
	end
	exit 1
}

function get_os_variant {
	OS_RELEASE=`rpm -qa  --queryformat '%{VERSION}\n'`
	ERRNO=$?
	OS_MAJOR_VERSION=${OS_RELEASE:(-3):1}
	OS_MINOR_VERSION=${OS_RELEASE:(-1):1}
	return $ERRNO
}

function get_default_fs {
	get_os_variant
	if [ $OS_MAJOR_VERSION == "6" ]; then
		echo ext4
	else
		echo xfs
	fi
}
## END: Standart Functions

DEFAULT_MOUNTPOINT='/data'
DEFAULT_FSTYPE=$(get_default_fs)
DEFAULT_DEVICE[0]='/dev/sdb'
DEFAULT_DEVICE[1]='/dev/vdb'
DEFAULT_DEVICE[2]='/dev/xvdb'

## check active user
if [ `whoami` != "root" ]; then
	die "Error: run script angain under root user"
fi

### process options
while getopts d:m:t:h opt
do
	case $opt in
	d)	opt_device=1; device=$OPTARG ;;
	m)	opt_mountpoint=1; mountpoint=$OPTARG ;;
	t)	opt_fstype=1; fstype=$OPTARG ;;
	h|?)	usage ;;
	esac
done

if (( ! opt_fstype )); then
	fstype=$DEFAULT_FSTYPE
fi

if (( ! opt_device )); then

	for i in ${DEFAULT_DEVICE[@]}; do
                if [ -b $i ]; then
                        device=$i
                fi
        done
fi

if (( ! opt_mountpoint )); then
	mountpoint='/data'
fi


### select awk
[[ -x /usr/bin/mawk ]] && awk='mawk -W interactive' || awk=awk

## check mountpoint
if [ -d $mountpoint ]; then
	rmdir $mountpoint || die "Mountpoint: $mountpoint not empty."
	mkdir -p $mountpoint || die "Can't create mounpoint: $mounpoint"
else
	mkdir -p $mountpoint || die "Can't create mounpoint: $mounpoint"
fi

if [ -b $device ]; then
	# get partition table
	partition_table=`parted -s $device print | awk '/Partition Table/ {print $3}'` 2> /dev/null
	if [ $partition_table != 'unknown' ]; then
		die "Error: Disk: $device have a valid partition table and may contain a data. STOP execution"
	fi
	parted -s $device mklabel gpt > /dev/null 2>&1 || die "can't label device $device"
	parted -s $device mkpart primary 0% 100% > /dev/null 2>&1 || die "can't create data partition"
	partprobe /dev/sdb
else
	die "Device: $device does not exist"
fi


mkfs -t $fstype ${device}1  > /dev/null 2>&1 || die "Error: Can't create filesystem: $fstype on device: $device"

echo "${device}1 $mountpoint $fstype defaults 0 0" >> /etc/fstab || die "Error: Can't write to /etc/fstab file"

mount $mountpoint || die "Error: Can't mount filesystem on device $device"