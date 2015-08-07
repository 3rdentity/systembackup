#!/bin/bash
#Incremental Backup Script

# Get config
source /home/owen/bin/backup/systembackup.conf

# Current date with hours, ISO-8601 format
CURRENT_TIME=`date -Ihours`

# Last backup date
LASTBACKUP=$(ls $TARGET_DIR | tail -n 1)

# Link directory
LNK="--link-dest=$TARGET_DIR/$LASTBACKUP"

# Backup location
TRG="$TARGET_DIR/$CURRENT_TIME"

# Rsync options
# Archive, hardlink, delete
OPT="-ah --delete"

# Run backup
# Check if the backup loaction already exists
if [ $CURRENT_TIME != $LASTBACKUP ]
then
	echo "local rsync $OPT $LNK $SOURCE_DIR $TRG"
	rsync $OPT $LNK $SOURCE_DIR $TRG
else
	echo "local rsync $OPT $SOURCE_DIR $TRG"
	rsync $OPT $SOURCE_DIR $TRG
fi

# Keep a list of installed packages.
# If package list already exists, recreate it.
# Allows script to be run manually without error.
# Native packages.
if [ -e $TRG/pkglist.txt ]
then
	rm $TRG/pkglist.txt
fi
pacman -Qqen > $TRG/pkglist.txt

# AUR packages
if [ -e $TRG/pkglist_aur.txt ]
then
	rm $TRG/pkglist_aur.txt
fi
pacman -Qqem > $TRG/pkglist_aur.txt

# Only keep a linited number of backups
while [ $(ls $TARGET_DIR | wc -l) -gt $BACKUPS_TO_KEEP ]
do
	echo "deleting $TARGET_DIR/$(ls $TARGET_DIR | head -n 1)"
	rm -rf $TARGET_DIR/$(ls $TARGET_DIR | head -n 1)
done

# Copy the backup to the remote server.
# This does not create a new backup, 
# but used the backup that was just made.
if [ $REMOTE_BACKUP = true ]
then
	REMOTE_LAST_BACKUP=$(ssh -o "BatchMode yes" -i $SSH_ID $REMOTE_USER@$REMOTE_SERVER ls $REMOTE_DIR | tail -n 1)
	REMOTE_LAST="$REMOTE_DIR/$REMOTE_LAST_BACKUP"
	REMOTE_TRG="$REMOTE_DIR/$CURRENT_TIME"

	if [ $REMOTE_LAST_BACKUP != $CURRENT_TIME  ]
	then
		echo "remote directory cp --reflink=auto -rp $REMOTE_LAST $REMOTE_TRG"
		ssh -o "BatchMode yes" -i $SSH_ID $REMOTE_USER@$REMOTE_SERVER sudo cp --reflink=auto -rp $REMOTE_LAST $REMOTE_TRG
		echo "remote rsync -ze ssh -i $SSH_ID $OPT --inplace $TRG $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR"
		rsync -ze "ssh -i $SSH_ID" $OPT --inplace $TRG $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR 
	else
		echo "remote rsync -ze ssh -i $SSH_ID $OPT $TRG $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR"
		rsync -ze "ssh -i $SSH_ID" $OPT $TRG $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR 
	fi

	# Only keep a limited number of backups 
	# on the remote server
	while [ $(($(ssh -o "BatchMode yes" -i $SSH_ID $REMOTE_USER@$REMOTE_SERVER ls $REMOTE_DIR | wc -l))) -gt $(($REMOTE_BACKUPS_TO_KEEP)) ]
	do
		REMOTE_DIRECTORY_TO_DELETE=$(ssh -o "BatchMode yes" -i $SSH_ID $REMOTE_USER@$REMOTE_SERVER ls $REMOTE_DIR | head -n 1)
		echo "deleteing $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR/$REMOTE_DIRECTORY_TO_DELETE"
		ssh -o "BatchMode yes" -i $SSH_ID $REMOTE_USER@$REMOTE_SERVER sudo rm -rf $REMOTE_DIR/$REMOTE_DIRECTORY_TO_DELETE
	done
fi
