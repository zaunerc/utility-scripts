#!/bin/sh

set -e

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <git directory> <file system group>"
	exit
fi

DIR="$1"
GROUP="$2"

# Change ownership of files and directories
#
chown -R root:"$GROUP" "$DIR"

# Set setgid bit. This will make all newly created files inherit the
# parent directory's group, instead of the user's.
#
find "$DIR" -type d -exec chmod g+s {} \;

# Set dir and file permissions.
#
find "$DIR" -type d -exec chmod 775 {} \;
find "$DIR" -type f -exec chmod 664 {} \;

# Set default group permissions for new dirs (ignores UMASK settings)
#
find "$DIR" -type d -exec setfacl -m "default:group::rwx" {} \;

