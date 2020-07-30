#!/bin/bash
#
# Copyright (C) 2020 Thomas Mueller <developer@mueller-dresden.de>
#
# This code is free software. You can use, redistribute and/or
# modify it under the terms of the GNU General Public Licence
# version 2, as published by the Free Software Foundation.
# This program is distributed without any warranty.
# See the GNU General Public Licence for more details.
#


#
# PARAMETERS
#

# path and name of the directory for the new backups
BACKFILEDIR='./backup_files'

# number of the first blocks of the disk to save, by using MBR (the first blocks can contain important data for the boot loader)
NumSavBlocksDISK=10000

# directory of the partclone applications (if the string empty, use the local applications)
# partclonePath="./partclone-bin/"
partclonePath=""

# the name and part of the restore script
restoreFile='./restore.sh'

# split size (MB) for backup files
SPLITSIZEMB='1000'

# default disc to backup, by using the option "--auto"
# DISC='/dev/nvme0n1'
DISC='/dev/sda'


#
# START the current script
#

# check if partclone is installed
if [ -n ${partclonePath} ]; then partclonePath=`dirname $(which partclone.restore)`'/'; fi
if [ ! -e ${partclonePath}partclone.restore ]
then
	echo "ERROR: UNABLE TO FIND the PARTCLONE (https://partclone.org/) tools in the directory '${partclonePath}'."
	echo "       Install the (static compiled) partclone tools to '${partclonePath}' OR update the path to the tools in this backup script."
	exit -1
fi

# warning, that there is no warranty
clear
echo -e "\nTHIS PROGRAM IS DISTRIBUTED WITHOUT ANY WARRANTY.\nYOU CAN ONLY USE IT ON YOUR OWN RISK.\n"
sleep 5

# if not using "--auto" let the user ask somethink
if [ "$1" != "--auto" ]
then
	# let the user choose the disk
	CONTINUE='n'
	while [ $CONTINUE != 'y' ]
	do
		echo -e "Following devices was found on the system:\n"
		lsblk | grep disk | awk '{ print NR " /dev/" $1 " (" $4 ")" }'
		MaxDevices=`lsblk | grep disk | wc -l`
		echo -e -n "\nPlease type the number of the device to backup (or break with a wrong number): "; read USERINPUT
		if [ $USERINPUT -le 0 ]; then "Error: unknown device"; exit 0; fi
		if [ $USERINPUT -gt $MaxDevices ]; then "Error: unknown device"; exit 0; fi
		if [ $USERINPUT -gt 0 ]; then CONTINUE='y'; else "Error: unknown device"; exit 0; fi
		DISC='/dev/'`lsblk | grep disk | awk '{ print $1 }' | head -n $USERINPUT | tail -n 1`
	done
	
	# ask the user if the backup should start now
	echo -e -n "\nDo you want to make a backup of $DISC now (y/n)? "
	read USERINPUT
	if [ $USERINPUT != y ]
	then
		echo "OK, stop now."
		exit -1
	fi
	echo
else
	echo -e "Starting automatic backup of $DISC, now.\n"
fi

# create backup directory
if [ -e "$BACKFILEDIR" ]
then
	echo "ERROR: COULD NOT CREATE the NEW DIRECTORY '$BACKFILEDIR'."
	echo "If the directory still exists, please rename or remove it."
	echo -e "Nothing changed.\n"
	exit -1
else
	mkdir $BACKFILEDIR || (echo -e "\nERROR: COULD NOT CREATE the NEW DIRECTORY '$BACKFILEDIR'\n. Continue anyway."; sleep 5)
fi

#
# START the RESTORE SCRIPT and continue it later
#
echo '#!/bin/bash' > $restoreFile
echo '
date
echo -e "\nTHIS PROGRAM IS DISTRIBUTED WITHOUT ANY WARRANTY.\nYOU CAN ONLY USE IT ON YOUR OWN RISK.\n"
sleep 3
echo -e "Currently partitions on $DISC:\n"
parted '$DISC' print free

if [ "$1" != "--auto" ]
then
	echo -n "WARNING: Should ALL DATA FROM '$DISC' BE ERASED now, to try reinstalling the disk from the backup (y/n)? "
	read USERINPUT
	if [ "$USERINPUT" != y ]
	then
		  echo "OK, stop now. Nothing was changed."
		  exit -1
	fi
	
	echo -n "Should the disk be overwritten with zero bytes, before reinstalling the backup (y/n)? "
	read USERINPUT
	echo -e "\nThe disk will erasure in 15 seconds. Last chance to abord, with [CTRL] + [C]."
	sleep 15
	if [ "$USERINPUT" == y ]
	then
		echo -e "\n... cleaning the disk with zero bytes"
		shred -v -z -n 0 '$DISC'
	fi
fi

' >> $restoreFile


#
# save the partition configuration
#
echo "Saving the partition table ..."

# MBR type
if [ `parted $DISC print | grep 'Partition Table:' | awk -F ': ' '{ print $2 }'` == 'msdos' ]
then
   # save the MBR partition table
   sfdisk -d $DISC > $BACKFILEDIR/partitions.sfdisk
    
   # save the first blocks of the disk (this can contains the boot loader)
   echo -"... saving the first $NumSavBlocksDISK blocks of $DISK"
   dd if=$DISC of=$BACKFILEDIR/first.dd.blocks bs=512 count=$NumSavBlocksDISK
    
   # save the partition table with parted (only for reading it manually)
   parted $DISC unit s print free > $BACKFILEDIR/partitions.parted
   parted $DISC print free >> $BACKFILEDIR/partitions.parted

   # continue the restore script
   echo '
   echo -e "\n... use dd to restore the first blocks"
   dd if='$BACKFILEDIR'/first.dd.blocks of='$DISC'
   sleep 3
   partprobe '$DISC'

   echo -e "\n... use sfdisk to restore the partition table"
   sfdisk -f '$DISC' < '$BACKFILEDIR'/partitions.sfdisk
   sleep 3
   partprobe '$DISC'
   
   ' >> $restoreFile
fi

# GPT type
if [ `parted $DISC print | grep 'Partition Table:' | awk -F ': ' '{ print $2 }'` == 'gpt' ]
then
   # save the GPT partition table
   sgdisk -b partitions.sgdisk $DISC
    
   # save the partition table with parted (only for reading it manually)
   gdisk -l $DISC > partition_informations_gdisk.txt
   parted $DISC unit s print free > partitions.parted
   parted $DISC print free >> partitions.parted

   # continue the restore script
   echo '
   echo -e "\n... use sfdisk to restore the partition table and create a new GUID"
   sgdisk -g -l partitions.sgdisk '$DISC'
   sleep 3
   sgdisk -G
   sleep 3
   partprobe '$DISC'
   set +x

   ' >> $restoreFile
fi


#
# let the user to choose the compression level (or no compression)
#
if [ "$1" != "--auto" ]
then
	# if not using "--auto" ask the user
	echo -e -n "\nShould the backups be compressed ( NOT / gzip / multicore pigz) (compression level) (n/g1/g6/g9/p1/p6/p11) (p6 is default) ? "
	read USERINPUT
	COMPRESSCMD=''
	if [ "$USERINPUT" = '' ]; then USERINPUT='p6'; fi
	if [ "$USERINPUT" = 'n' ]; then COMPRESSCMD=''; SUFFIX=''; fi
	if [ "$USERINPUT" = 'g1' ]; then COMPRESSCMD='| gzip -1 -c'; SUFFIX='.gz'; fi
	if [ "$USERINPUT" = 'g6' ]; then COMPRESSCMD='| gzip -6 -c'; SUFFIX='.gz'; fi
	if [ "$USERINPUT" = 'g9' ]; then COMPRESSCMD='| gzip -9 -c'; SUFFIX='.gz'; fi
	if [ "$USERINPUT" = 'p1' ]; then COMPRESSCMD='| pigz -1 -c'; SUFFIX='.gz'; fi
	if [ "$USERINPUT" = 'p6' ]; then COMPRESSCMD='| pigz -6 -c'; SUFFIX='.gz'; fi
	if [ "$USERINPUT" = 'p11' ]; then COMPRESSCMD='| pigz -11 -c'; SUFFIX='.gz'; fi
else
	# the default value by using "--auto"
	COMPRESSCMD='| pigz -6 -c'; SUFFIX='.gz';
fi

#
# let the user choose if the backup should split
#
SPLITCMD='>'
CONTINUE='n'
if [ "$1" != "--auto" ]
then
	while [ $CONTINUE != 'y' ]
	do
		 echo -n "Should the backup files be splitted to ${SPLITSIZEMB} MB parts (y/n) ? "
		 read SPLIT
		 if [ $SPLIT == 'y' ]; then SPLITCMD=' | split -d -b '$SPLITSIZEMB'm -a 5 -'; CONTINUE='y'; fi
		 if [ $SPLIT == 'n' ]; then CONTINUE='y'; fi
	done
fi
echo


#
# create the restore part for the SWAP partition
#
echo '
   echo -e "\n... restore the swap partition(s)"
   ' >> $restoreFile

parted $DISC print | grep 'swap' | awk -v DISC=$DISC -F ' ' '{ print "   mkswap " DISC $1 }' >> $restoreFile

echo '
   echo -e "\n... restore the partition table"
' >> $restoreFile


#
# find the type of partition style (MBR or GPT)
#
partitionsNumbersAndTyps='unknown'
if [ `parted $DISC print | grep 'Partition Table:' | awk -F ': ' '{ print $2 }'` = 'msdos' ]
then
	partitionsNumbersAndTyps=`parted $DISC print | sed -n '/Number/,//p' | grep 'primary\|logical' | awk '{ print $1 ":" $6 }'`
fi
if [ `parted $DISC print | grep 'Partition Table:' | awk -F ': ' '{ print $2 }'` = 'gpt' ]
then
   partitionsNumbersAndTyps=`parted $DISC print | sed -n '/Number/,//p' | grep -v '^Number\|^$' | awk '{ print $1 ":" $5 }'`
fi
if [ "$partitionsNumbersAndTyps" = 'unknown' ]
then
	echo "Partition type '$partitionsNumbersAndTyps' unknown, stop here."
	exit -1
fi 


#
# for all partitions, create the save and restore script ($i contains the partition number and type)
#
echo '
   echo -e "\n... restoring partitions\n"
' >> $restoreFile

echo -e "\nAnalysing partition types ...\n"
for i in $partitionsNumbersAndTyps
do

	# split all lines in number and type of partition
	PartNumber=`echo $i | awk -F ':' '{ print $1 }'`
	PartNumber=`if [ -e "${DISC}${PartNumber}" ]; then echo "$PartNumber"; else ls -1 ${DISC}?${PartNumber} | sed "s|${DISC}||g"; fi`   # a fix for NVME discs
	PartType=`echo $i | awk -F ':' '{ print $2 }'`
   BackupFileName=`echo backup$DISC | sed 's/\//_/g'`

	# if the partition type is EXT[2|3|4]
	if [[ -n `echo $PartType | grep 'ext2\|ext3\|ext4'` ]]
	then
		echo "${partclonePath}partclone.extfs -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
      continue
	fi

	# if the partition type is BTRFS
	if [[ -n `echo $PartType | grep 'btrfs'` ]]
	then
		echo "${partclonePath}partclone.btrfs -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
      continue
	fi

	# if the partition type is XFS
	if [[ -n `echo $PartType | grep 'xfs'` ]]
	then
		echo "${partclonePath}partclone.xfs -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
      continue
	fi
        
	# if the partition type is NTFS
	if [[ -n `echo $PartType | grep 'ntfs'` ]]
	then
		echo "${partclonePath}partclone.ntfs -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
		continue
	fi

	# if the partition type is FAT*
	if [[ -n `echo $PartType | grep 'fat'` ]]
	then
		echo "${partclonePath}partclone.fat -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
		continue
	fi

	# if the partition type is HFS+ (Mac OS X Type)
	if [[ -n `echo $PartType | grep 'hfs+'` ]]
	then
		echo "${partclonePath}partclone.hfsp -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
		continue
	fi
    
	# if the partition type is EXFAT (possible the type could not be analyse correctly)
	if [[ -n `sfdisk -d $DISC | grep "$DISC$PartNumber" | grep 'type=7'` ]]
	then
		echo "${partclonePath}partclone.exfat -c -d -s $DISC$PartNumber -L $BACKFILEDIR/$BackupFileName$PartNumber.partclone.log $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.partclone$SUFFIX" >> $BACKFILEDIR/save_command.sh
		echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.partclone${SUFFIX}"'*'" | pigz -d | ${partclonePath}partclone.restore -d -s - -o $DISC$PartNumber" >> $restoreFile
		continue
	fi

	# if the partition is the SWAP type
	if [[ -n `echo $PartType | grep 'swap'` ]]
	then
		echo -e "Ignoring the content of the SWAP partition '$DISC$PartNumber'."
		continue
   fi

	# if the partition type is could not be found
	echo "Could not sure understand the type of the partition $DISC$PartNumber . Backup this partition by using 'partclone.dd', later."
	echo "dd if=$DISC$PartNumber bs=10M | pv $COMPRESSCMD $SPLITCMD $BACKFILEDIR/$BackupFileName$PartNumber.dd$SUFFIX" >> $BACKFILEDIR/save_command.sh
   echo "   cat $BACKFILEDIR/$BackupFileName$PartNumber.dd$SUFFIX"'*'" | pigz -d | pv | dd of=$DISC$PartNumber bs=10M" >> $restoreFile

done

echo '
   sleep 3
   echo -e "\n... reading the new partition table"
   partprobe '$DISC'
   sleep 3
   
echo -e "\nThe backup was restored now, hopefully.\n"
date
if [ -x ./custom.sh ]
then
	/bin/bash ./custom.sh
fi
exit 0
' >> $restoreFile


#
# START THE BACKUP NOW
#
echo -e "\nStarting backup of the partitions with the following commands in 5 seconds:\n"
cat $BACKFILEDIR/save_command.sh
echo
sleep 5
echo
echo -e "Backup the partitions now. Please wait ...\n"
bash $BACKFILEDIR/save_command.sh


#
# last steps and last output
#

# make the restore script startable
chmod 700 $restoreFile

# get informations about the backup files 
echo -e "\nThe backup processes was finished. The following files was created:\n"
ls -lRh $BACKFILEDIR $restoreFile
echo -e "\nPlease check the files sizes and the output to find errors, now !\n"

# grep the log files for typical error messages
echo; echo "Extract of the log files from partclone:"; echo
cat $BACKFILEDIR/$BackupFileName*.partclone.log | grep "/dev/$BackupFileName\|successfully\|write error\|is mounted at\|error exit"

exit 0
