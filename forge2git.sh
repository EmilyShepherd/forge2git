#!/bin/sh
#
# Copyright (c) 2015 Emily Shepherd
# Free usage, open license etc. No warrenty implied
#
# Scrapes ECS Forge project HTML pages and converts them to git
# repos
#

# Forge settings
COMMIT_URL="https://forge.ecs.soton.ac.uk/plugins/scmsvn/viewcvs.php"
BLOB_URL="${COMMIT_URL}/*checkout*/"

usage()
{
	echo "usage: forge2git [-h|--help]"
	echo "                 <projname> [--dir|-d <directory>] [--names|-n <name>]"
	echo ""
	echo "Pass in your ECS Forge project name as your first argument."
	echo "  EG: forge2git os12-ams2g11"
	echo ""
	echo "The author of the git commit defaults to \"ecsid <ecsid@ecs.soton.ac.uk>\". To"
	echo "override this, provide a names database: a text file with each line in the form:"
	echo "  ^ecsid Human Readable Name <correct@email.address>$"
	echo ""
	echo "Optional Arguments"
	echo "    --dir -d    The following argument is the name of the directory to create"
	echo "                and intialise as a git repo. Defaults to the project name."
	echo ""
	echo "    --names -n  The following argument is the filename of a names database used"
	echo "                to convert ECS IDs to git authors."

	exit 1
}

shift_and_get()
{
	shift

    if test -z "$1"
	then
        usage
    fi
    
    return $1
}

shut_down()
{
	cd ..
	rm -r $dir
	rm $tmp_file
	exit 1
}

# We require the first arg
if test -z "$1"
then
	usage
fi

if test $1 = "--help" || test $1 = "-h"
then
	usage
fi

proj=$1
shift

while test $# != 0
do
    case "$1" in
        -d|--dir)
            dir=$(shift_and_get) ;;
        -n|--names)
            names=$(shift_and_get) ;;
        *)
            usage
    esac
    shift
done

if test -z "$dir"
then
	dir=$proj
fi

if test -d "$dir"
then
	echo "Directory '$dir' already exists!"
	exit 1
fi

# Make it
mkdir $dir
cd $dir
git init

tmp_file=$(mktemp)

echo "Contacting ECS Forge..."

# Get the revs
curl -kso $tmp_file "$COMMIT_URL?root=$proj"
revs=$(sed -n 's/.*value\="\([0-9]\+\)".*/\1/p' $tmp_file)

if test -z $revs
then
	echo "Project '$proj' not found!"
	shut_down
fi

# Loop over the revs
i=1
while ! test $i = $(expr $revs + 1)
do
	# Load the revision page and parse its details
	curl -kso $tmp_file "$COMMIT_URL?root=$proj&rev=$i&view=rev"
	author=$(sed -rn '/<th>Author\:<\/th>/{:a;N;/<td>.*<\/td>/{//p;d};ba}' $tmp_file | sed -n 's/<td>\(.*\)<\/td>/\1/p')
	msg=$(sed -n 's/.*vc_log">\(.*\)<.*/\1/p' $tmp_file)
	date=$(sed -n 's/<td>\(.*\)<i>(.*/\1/p' $tmp_file)
	git_author=

	# Lookup the name in the table
	if ! test -z "$names"
	then
		cd ..
		git_author=$(sed -n "s/$author \(.*\)/\1/p" $names)
		cd $dir
	fi

	# If we don't have a git author, make it up
	if test -z "$git_author"
	then
		git_author="$author <$author@ecs.soton.ac.uk>"
	fi

	# SVN allows blank messages because blegh
	if test -z "$msg"
	then
		msg="(Empty Message)"
	fi

	# For all the files in this revision, download and stage them with git
	for file in $(sed -n 's/.*view\=markup">\(.*\)<.*/\1/p' $tmp_file)
	do
		# If this has subdirectories, we need to loop through them and
		# create them if they don't already exist on our local machine
		path=.
		for part in $(echo $file | tr "/" "\n" | head -n -1)
		do
			path="$path/$part"
			if ! test -d "$path"
			then
				mkdir $path
			fi
		done

		curl -kso $file "${BLOB_URL}${file}?rev=$i&root=$proj"

		# For empty files, it seems ECS Forge outputs a header by mistake
		# This does mean that if you happen to have a file with the first line
		# "Content-Type: text/plain", this tool may not work as you expect
		#
		# ...Submit a report if this is an issue
		if test "$(head -n 1 $file)" = "Content-Type: text/plain"
		then
			cat /dev/null > $file
		fi

		git add $file >> /dev/null 2>&1
	done

	# Revision complete, commit it!
	git commit --quiet --author="$git_author" --date="$date" -m "$msg"

	# Print out a "nice" loading bar
	percent=$(awk "BEGIN {printf \"%.0f\", $i / $revs * 100}")
	hashes=$(awk "BEGIN {printf \"%.0f\", $percent / 2}")
	spaces=$(expr 50 - $hashes)

	echo -n "["

	for (( j=0; j<$hashes; j++ ))
	do
		echo -n "#"
	done

	for (( j=0; j<$spaces; j++ ))
	do
		echo -n " "
	done

	echo -ne "] (${percent}%)\r"

	# Inc
	i=$(expr $i + 1)
done

# Tidy Up
rm $tmp_file

echo ""
echo "Complete"