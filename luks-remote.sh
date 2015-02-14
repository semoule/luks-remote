#!/bin/bash

# LICENSING
#------------------------------------------------------------------------------
# DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#         Version 2, December 2004
#
# Copyright (C) 2014 Semoule
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
# DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
# TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
# 0. You just DO WHAT THE FUCK YOU WANT TO.
#------------------------------------------------------------------------------

# ABSTRACT
#------------------------------------------------------------------------------
# v1.1
#
# This humble script should help you to manage remote LUKS container over ssh
# You can create/extend/mount/umount/fsck remote container
# You can also rsync to container.
# The basic idea is to turn untrusted remote servers as private backup devices
# You can either use a config file or only use arguments
# Tested on Debian based distro.
#------------------------------------------------------------------------------

## GLOBALS
dir=$(dirname $0)
user=$(who am i | awk '{print $1}')
unset force

## CONF
if [ -f $dir/luks-remote.conf ] ;then source $dir/luks-remote.conf ;fi

## FUNCTIONS
ssh_mount()
{
	local ruser=$1
	local rserver=$2
	local rpath=$3
	local lpath=$4

	sshfs $ruser@$rserver:$rpath $lpath -o uid=$(id -u $LOCALUSER),reconnect,allow_root,direct_io
	return $?
}
ssh_umount()
{
	local lpath=$1

	fusermount -u $lpath
	return $?
}
luks_mount()
{
	local luks_file=$1
	local mountdir=$2
	local dev=$(sudo losetup -f)

	sudo losetup $dev $luks_file                             &&
	sudo mkdir -p $mountdir                                  &&
	sudo chown $user:$user $mountdir                         &&
	sudo chmod 770 $mountdir                                 &&
	sudo cryptsetup luksOpen $dev $(basename $luks_file)     &&
	sudo mount -t ext4 -o noatime,nodiratime,commit=1,errors=remount-ro,barrier=1,data=ordered /dev/mapper/$(basename $luks_file) $mountdir
	return $?
}
luks_umount()
{
	local luks_file=$1
	local mountdir=$2
	local dev=$(sudo losetup -a | grep $luks_file | cut -d ":" -f1)
	
	sudo umount /dev/mapper/$(basename $luks_file)   &&
	sudo rmdir $mountdir                             &&
	sudo cryptsetup luksClose $(basename $luks_file) &&
	sleep 2                                          &&
	sudo losetup -d $dev
	return $?
}
luks_fsck()
{
	local luks_file=$1
	local dev=$(sudo losetup -f)
	if [ $force ]; then
		fsck_option="-f"
	else
		fsck_option="-nv"
	fi

	sudo losetup $dev $luks_file                                   &&
	sudo cryptsetup luksOpen $dev $(basename $luks_file)           &&
	sudo fsck.ext4 $fsck_option /dev/mapper/$(basename $luks_file) &&
	sudo cryptsetup luksClose $(basename $luks_file)               &&
	sleep 2                                                        &&
	sudo losetup -d $dev
	return $?
}
luks_resize()
{
	local luks_file=$1
	local dev=$(sudo losetup -f)
	local wsize=$2

	sudo dd if=/dev/zero bs=1M count=$wsize of=$luks_file oflag=append conv=notrunc &&
	sleep 2                                                                         &&
	sudo losetup $dev $luks_file                                                    &&
	sudo cryptsetup luksOpen $dev $(basename $luks_file)                            &&
	sudo cryptsetup resize $(basename $luks_file)	                                &&
	sleep 2                                                                         &&
	sudo fsck.ext4  -v /dev/mapper/$(basename $luks_file)                           &&
	sleep 2                                                                         &&
	sudo resize2fs /dev/mapper/$(basename $luks_file)                               &&
	sleep 2                                                                         &&
	sudo fsck.ext4 -nv /dev/mapper/$(basename $luks_file)                           &&
	sleep 2                                                                         &&
	sudo cryptsetup luksClose $(basename $luks_file)                                &&
	sleep 2                                                                         &&
	sudo losetup -d $dev

	return $?
}
luks_create()
{
	local luks_file=$1
	local dev=$(sudo losetup -f)
	local wsize=$2

	sudo dd if=/dev/zero bs=1M count=$wsize of=$luks_file oflag=append conv=notrunc &&
	sleep 2                                                                         &&
	sudo losetup $dev $luks_file                                                    &&
	sudo cryptsetup -c aes-cbc-essiv:sha256 luksFormat $dev                         &&
	sudo cryptsetup luksOpen $dev $(basename $luks_file)                            &&
	sleep 2                                                                         &&
	sudo mkfs.ext4 /dev/mapper/$(basename $luks_file)                               &&
	sleep 2                                                                         &&
	sudo cryptsetup luksClose $(basename $luks_file)                                &&
	sleep 2                                                                         &&
	sudo losetup -d $dev

	return $?
}
luks_status()
{
	echo
	echo "... check sshfs mount status ..."
	cat /proc/mounts | grep $ruser@$rserver:$rpath && echo "OK" || echo "KO"

	echo
	echo "... check loopback device status ..."
	sudo losetup -a | grep $luks_container && echo "OK" || echo "KO"

	echo
	echo "... check luks container mount status ..."
	cat /proc/mounts | grep $luks_mountpoint && echo "OK" || echo "KO"

	return $?
}
luks_rsync()
{
	local function_status=0

	if [ "$rsync_list" = "all" ]; then
		for (( i=0; i<${#RSYNC_SOURCE[@]}; i++ ));
		do
			echo
			echo "${RSYNC_BIN} ${RSYNC_ARGS} ${RSYNC_SOURCE[$i]} ${luks_mountpoint}/${RSYNC_TARGET[$i]}"
			      ${RSYNC_BIN} ${RSYNC_ARGS} ${RSYNC_SOURCE[$i]} ${luks_mountpoint}/${RSYNC_TARGET[$i]}
			let function_status=$function_status+$?
		done
	else
		if [ $rsync_list -ge ${#RSYNC_SOURCE[@]} ]; then
			echo
			echo "warning : rsync slot empty. exiting!"
			function_status=1
		else
			echo
			echo "${RSYNC_BIN} ${RSYNC_ARGS} ${RSYNC_SOURCE[$rsync_list]} ${luks_mountpoint}/${RSYNC_TARGET[$rsync_list]}"
			      ${RSYNC_BIN} ${RSYNC_ARGS} ${RSYNC_SOURCE[$rsync_list]} ${luks_mountpoint}/${RSYNC_TARGET[$rsync_list]}
			let function_status=$function_status+$?
		fi
	fi
	return $function_status
}
usage()
{
	echo
	echo "Usage: $0 mount|umount|status|fsck|resize (MB)|create (MB)|rsync"
	echo
	echo "-u | --remote-user LOGIN      : use LOGIN to connect to remote ssh server"
	echo "-s | --remote-server IP       : use IP as remote ssh server"
	echo "-p | --remote-path REMOTEPATH : mount REMOTEPATH from remote ssh server"
	echo "-c | --container FILENAME     : use FILENAME luks container"
	echo "-m | --ssh-mountpoint PATH    : use local PATH as mountpoint for ssh server"
	echo "-l | --luks-mountpoint PATH   : use local PATH as mountpoint for luks opened container"
	echo "-f | --force                  : force fsck"
	echo "-r | --rsync-slot INDEX       : rsync only the slot specified"
	echo "-h | --help                   : display this help"
	echo
}

## MAIN
# parse arguments
arguments=`getopt -o c:fhl:m:p:r:s:u: --long container:,force,help,luks-mountpoint:,ssh-mountpoint:,remote-path:,remote-server:,remote-user:,rsync-slot:, -n "$0" -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$arguments"
while true ; do
    case "$1" in
        -c|--container)
            custom_container=$2
            shift 2
            ;;
		-f|--force)
			force=1
			shift
			;;
        -h|--help)
			usage
            exit 1
            ;;
		-l|--luks-mountpoint)
			custom_luksmountpoint=$2
			shift 2
			;;
		-m|--ssh-mountpoint)
			custom_sshmountpoint=$2
			shift 2
			;;
		-p|--remote-path)
			custom_remotepath=$2
			shift 2
			;;
		-r|--rsync-slot)
			custom_rsync=$2
			shift 2
			;;
		-s|--remote-server)
			custom_remoteserver=$2
			shift 2
			;;
		-u|--remote-user)
			custom_remoteuser=$2
			shift 2
			;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# set overrides if specified
ruser=${custom_remoteuser:-$RUSER}
rserver=${custom_remoteserver:-$RSERVER}
rpath=${custom_remotepath:-$RPATH}
lpath=${custom_sshmountpoint:-$LPATH}
luks_container=${custom_container:-$LUKS_CONTAINER}
luks_mountpoint=${custom_luksmountpoint:-$LUKS_MOUNTPOINT}
rsync_list=${custom_rsync:-all}

# show config
echo "remote luksfile : ssh://$ruser@$rserver:$rpath/$luks_container"
echo "local ssh path  : $lpath"
echo "local luks path : $luks_mountpoint"
echo
echo "Rsync slots :"
for (( i=0; i<${#RSYNC_SOURCE[@]}; i++ ));
do
	printf '%-4s %-50s %-3s %-50s\n' "[$i]" "${RSYNC_SOURCE[$i]}" "-->" "${luks_mountpoint}/${RSYNC_TARGET[$i]}"
done

# parse command
case $1 in
	mount)
		echo "mounting"
		ssh_mount $ruser $rserver $rpath $lpath            &&
		luks_mount $lpath/$luks_container $luks_mountpoint &&
		echo "success." || echo "failed."
		;;
	umount)
		luks_umount $luks_container $luks_mountpoint       &&
		ssh_umount $lpath                                  &&
		echo "success." || echo "failed."
		;;
	fsck)
		echo "fsck"
		ssh_mount $ruser $rserver $rpath $lpath            &&
		luks_fsck $lpath/$luks_container                   &&
		ssh_umount $lpath                                  &&
		echo "success." || echo "failed."
		;;
	resize)
		echo "resize"
		ssh_mount  $ruser $rserver $rpath $lpath           &&
		luks_resize $lpath/$luks_container $2              &&
		ssh_umount $lpath                                  &&
		echo "success." || echo "failed."
		;;
	create)
		echo "create"
		ssh_mount  $ruser $rserver $rpath $lpath           &&
		luks_create $lpath/$luks_container $2              &&
		ssh_umount $lpath                                  &&
		echo "success." || echo "failed."
		;;
	status)
		luks_status
		;;
	rsync)
		luks_rsync
		;;
	*)
		usage
		exit 1  
		;;
esac
#EOF
