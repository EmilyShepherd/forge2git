#!/bin/sh

COMMIT_URL="https://forge.ecs.soton.ac.uk/plugins/scmsvn/viewcvs.php"
BLOB_URL="https://forge.ecs.soton.ac.uk/plugins/scmsvn/viewcvs.php/*checkout*/"

proj=$1
names="names.txt"
dir="_dir"

mkdir $dir
cd $dir
git init

tmp_file=$(mktemp)

curl -kso $tmp_file "$COMMIT_URL?root=$proj"

revs=$(sed -n 's/.*value\="\([0-9]\+\)".*/\1/p' $tmp_file)

i=1

while ! test $i = $(expr $revs + 1)
do
	curl -kso $tmp_file "$COMMIT_URL?root=$proj&rev=$i&view=rev"

	author=$(sed -rn '/<th>Author\:<\/th>/{:a;N;/<td>.*<\/td>/{//p;d};ba}' $tmp_file | sed -n 's/<td>\(.*\)<\/td>/\1/p')
	msg=$(sed -n 's/.*vc_log">\(.*\)<.*/\1/p' $tmp_file)
	date=$(sed -n 's/<td>\(.*\)<i>(.*/\1/p' $tmp_file)

	git_author=$(sed -n "s/$author \(.*\)/\1/p" ../$names)

	if test -z "$git_author"
	then
		git_author="$author <$author@ecs.soton.ac.uk>"
	fi

	for file in $(sed -n 's/.*view\=markup">\(.*\)<.*/\1/p' $tmp_file)
	do
		curl -kso $file "${BLOB_URL}${file}?rev=$i&root=$proj"

		if test "$(head -n 1 $file)" = "Content-Type: text/plain"
		then
			cat /dev/null > $file
		fi

		git add $file >> /dev/null 2>&1
	done

	git commit --quiet --author="$git_author" --date="$date" -m "$msg"

	percent=$(awk "BEGIN {printf \"%.0f\", $i / $revs * 100}")
	hashes=$(awk "BEGIN {printf \"%.0f\", $percent / 2}")
	spaces=$(expr 50 - $hashes)

	echo -ne "$(printf '#%.0s' {1..$hashes})$(printf ' %.0s' {1..$spaces}) (${percent}%)\r"

	i=$(expr $i + 1)
done

// Tidy Up
rm $tmp_file

echo -ne "\n"
echo ""
echo "Complete"