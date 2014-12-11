luks-remote
===========

Basic script to manage remote luks container over sshfs. The idea is to turn untrusted remote server as backup device.

Abstract :
	This humble script should help you to manage remote LUKS container over ssh
	You can create/extend/mount/umount/fsck remote container
	You can also rsync to container.
	You can either use a config file or only use arguments
	Tested on Debian based distro.


Manual :

1. install :
	# clone repository
	git clone https://github.com/semoule/luks-remote.git

	# install dependancies
	apt-get install cryptsetup rsync fuse sshfs

2. configure :
	# create config file to avoid use arguments
	cp luks-remote.conf.sample luks-remote.conf

	# edit and fill the file
	vi luks-remote.conf

3. Create the container
	./luks-remote.sh create 100

4. mount the container
	./luks-remote.sh mount

5. rsync to the container
	./luks-remote.sh rsync

6. umount the container
	./luks-remote.sh umount

7. troubleshooting

	the main problem is network outage while luks is remotely open.
	because the file system is journalized and mounted with barrier, problems are not as bad as it first looks like for your data.

	case 1 : network is recovered

	# check status
	./luks-remote.sh status

	# try umount
	./luks-remote.sh umount

	# check file system consistency
	./luks-remote.sh fsck



	case 2 : network is unrecoverable for now, I want to force close
	TODO
