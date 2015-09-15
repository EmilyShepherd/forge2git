#!/bin/sh

# Forge settings
COMMIT_URL="https://forge.ecs.soton.ac.uk/plugins/scmsvn/viewcvs.php"
BLOB_URL="https://forge.ecs.soton.ac.uk/plugins/scmsvn/viewcvs.php/*checkout*/"

usage()
{
	echo "$0 <projname> [--dir|-d <directory>] [--names|-n <name>]"
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

	# For all the files in this revision, download and stage them with git
	for file in $(sed -n 's/.*view\=markup">\(.*\)<.*/\1/p' $tmp_file)
	do
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
	echo -ne "$(printf '#%.0s' {1..${hashes}})$(printf ' %.0s' {1..${spaces}}) (${percent}%)\r"

	# Inc
	i=$(expr $i + 1)
done

# Tidy Up
rm $tmp_file

echo ""
echo "Complete"