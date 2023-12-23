#!/usr/bin/env bash
set -e

# heavily modified from github.com/jonascarpay/Wallpapers

# stackoverflow.com/a/296135731995812
quoteRe() {
	sed -e 's/[^^]/[&]/g; s/\^/\\^/g; $!a\'$'\n''\\n' <<<"$1" | tr -d '\n'
}

path_root="$(git rev-parse --show-toplevel)"
raw_root="https://raw.githubusercontent.com/buckmanc/Wallpapers/main"

tocMD="${path_root}/.internals/tableofcontents.md"
thumbnails_dir="${path_root}/.internals/thumbnails"
thumbnails_old_dir="${path_root}/.internals/thumbnails_old"
readmeTemplatePath="${path_root}/.internals/README_template.md"
fileListFile="${path_root}/.internals/filelist.md"

mkdir -p "$thumbnails_dir"
mv "$thumbnails_dir" "$thumbnails_old_dir"
mkdir -p "$thumbnails_dir"

rm "$tocMD" > /dev/null 2>&1 || true
rm "$fileListFile" > /dev/null 2>&1 || true

# TODO fix this up, support others
if [[ -f "$HOME/bin/find-images" ]]
then
	cp "$HOME/bin/find-images" "$path_root/scripts/find-images"
fi
if [[ -f "$HOME/bin/wallpaper-fitter" ]]
then
	cp "$HOME/bin/wallpaper-fitter" "$path_root/scripts/wallpaper-fitter"
fi

find-images() {
	"$path_root/scripts/find-images" "$@" -not -path '*/thumbnails*' -not -path '*/scripts/*'
}
find-images-main() {
	find-images "$path_root" -maxdepth 5 -mindepth 3 -not -path '*/.*'
}
wallpaper-fitter(){
	"$path_root/scripts/wallpaper-fitter" "$@"
}
bottom-level-dir(){
	if [[ "$(find-images "$1" -maxdepth 1 | wc -l)" -gt 0 ]]
	then
		echo 1
	else
		echo 0
	fi
}

fitDir="$path_root/.internals/wallpapers_to_fit"
imagesToFit="$(find-images "$fitDir")"
i=0
totalImagesToFit=$(echo "$imagesToFit" | wc -l)

echo "--checking for missing images to fit..."
echo "$imagesToFit" | while read -r src; do
	((i++)) || true
	if [[ -z "$src" ]]
	then
		continue
	fi
	filename="$(basename "$src")"
	printf '\033[2K%4d/%d: %s...' "$i" "$totalImagesToFit" "$filename" | cut -c "-$COLUMNS" | tr -d $'\n'

	target="${src/#"$fitDir"/"$path_root"}"
	# # temp fix: if jpeg target exists, burn it
	# if [[ -f "$target" ]] && echo "$target" | grep -Piq "\.jpe?g$"
	# then
	# 	rm "$target"
	# fi
	# swap jpegs to pngs to avoid a greyscaling bug
	target="$(echo "$target" | perl -pe 's/\.jpe?g$/.png/g')"
	targetDir="$(dirname "$target")"
	if [[ -f "$target" ]]
	then
		echo -en '\r'
		continue
	fi

	if echo "$src" | grep -iq "$fitDir/desktop"
	then
		args="--landscape"
	else
		args="--portrait"
	fi

	if echo "$src" | grep -iq "album cover art"
	then
		args+=" --blur"
	fi

	mkdir -p "$targetDir"
	wallpaper-fitter "$src" "$target" "$args"
	echo ""
done

echo -e "\r"

# if type pyphash-sort >/dev/null 2>&1
# then
# 	echo "calculating perceptual hash sort"
# 	echo "this could take a while"
# 	imgFiles="$(echo "$imgFiles" | pyphash-sort "(/forests/|/space/|/misc/|/leaves/)")"
# fi

# if perceptual hashing is available, append the hash to the start of the file for applicable categories
if type pyphash >/dev/null 2>&1
then
	echo -n "--checking for missing perceptual hash sort data..."
	imgFiles="$(find-images-main)"
	echo "$imgFiles" | while read -r path
	do
		filename="$(basename "$path")"
		if echo "$path" | grep -qiP "(/forests/|/space/|/misc/|/leaves/)" && ! echo "$filename" | grep -qiP '^[a-f0-9]{16}_'
		then
			echo -n "moving ${path}..."
			newPath="$(dirname "$path")/$(pyphash "$path")_$filename"
			mv --backup=numbered "$path" "$newPath"
			echo "done"
		fi

	done

	echo "done!"
fi


echo "--updating thumbnails..."

imgFiles="$(find-images-main)"
i=0
totalImages=$(echo "$imgFiles" | wc -l)

echo "$imgFiles" | while read -r src; do
	((i++)) || true
	filename="$(basename "$src")"
	printf '\033[2K%4d/%d: %s...' "$i" "$totalImages" "$filename" | cut -c "-$COLUMNS" | tr -d $'\n'

	target="${thumbnails_dir}/${src#"$path_root/"}"
	thumbnail_old="${thumbnails_old_dir}/${src#"$path_root/"}"

	target_dir="$(dirname "$target")"
	mkdir -p "$target_dir"

	echo    "${src#"$path_root"}" >> "$fileListFile"

	if [[ ! -f "$thumbnail_old" ]]; then
		if [[ "$src" == *"/mobile/"* ]]; then
			targetWidth=97
			aspectRatio="9/20"
		else
			targetWidth=200
			aspectRatio="16/9"
		fi

		targetHeight=$(echo "$targetWidth/($aspectRatio)" | bc -l)
		targetHeight="${targetHeight%%.*}"
		targetDimensions="${targetWidth}x${targetHeight}"

		# echo
		# echo "aspectRatio: $aspectRatio"
		# echo "targetDimensions: $targetDimensions"

		fitCaret="^"
		bgColor="none"

		# altered logic for images that sit in the center
		if echo "$src" | grep -iq "/floaters/"
		then
			fitCaret=""
			bgColor="black"
		fi

		# resize images, then crop to the desired resolution
		convert -background "$bgColor" -thumbnail "${targetDimensions}${fitCaret}" -unsharp 0x1.0 -gravity Center -extent "$targetDimensions" +repage "$src" "$target"

		echo ""
	else
		mv "$thumbnail_old" "$target"
		# echo "skipped!"
		echo -en "\r"
	fi
done

rm -rf "$thumbnails_old_dir"

echo ""

echo "--updating readme md's..."
# delete the folder readme files
find "$path_root" -maxdepth 5 -mindepth 2 -type f -iname 'readme.md' -delete

rootReadmePath="${path_root}/README_ALL.MD"
rm -f "$rootReadmePath"

directories="$(find "$path_root" -type d -not -path '*/.*' -not -path '*/scripts' -not -path '*/temp *' -not -path '*/thumbnails_test')"
totalDirs="$(echo "$directories" | wc -l)"
i=0
iDir=0
echo "$directories" | while read -r dir; do
	((iDir++)) || true
	friendlyDirName="${dir/"$path_root"}"
	# printf -v dirStatus '\033[2K%4d/%d: %s' "$iDir" "$totalDirs" "$friendlyDirName" | cut -c "-$COLUMNS" | tr -d $'\n'
	printf -v dirStatus '\033[2K%4d/%d: ' "$iDir" "$totalDirs"

	dirReadmePath="$dir/README.MD"
	# don't overwrite the real root readme
	if [[ "$dirReadmePath" == "${path_root}/README.MD" ]]
	then
		dirReadmePath="$rootReadmePath"
	fi

	imgFiles="$(find-images "$dir" -not -path '*/.*' -not -path '*/scripts')"
	i=0
	totalDirImages=$(echo "$imgFiles" | wc -l)

	bottomLevelDir="$(bottom-level-dir "$dir")"

	echo "# $(basename "$dir") - $(numfmt --grouping "$totalDirImages")" >> "$dirReadmePath"

	subDirs="$(echo "$imgFiles" | sed -r 's|/[^/]+$||' | sort -u)"
	echo "$subDirs" | while read -r subDir; do
		subDirName="${subDir#"$dir"}"
		subDirName="${subDirName#\/}"

		if [[ -z "$subDirName" ]]
		then
			continue
		fi
		customHeaderID="$(echo "${subDirName}" | perl -pe 's/[ -_"#]+/-/g')"
		imgFolderPathReggie="$(quoteRe "${subDir}/")"
		folderToc="- [$subDirName](#$customHeaderID) - $(echo "$imgFiles" | grep -iPc "$imgFolderPathReggie")"
		echo "$folderToc" >> "$dirReadmePath"
	done

	echo "$imgFiles" | while read -r imgPath; do
		((i++)) || true
		imgFilename="$(basename "$imgPath")"
		printf '%s %4d/%d: %s...' "$dirStatus" "$i" "$totalDirImages" "$friendlyDirName" | cut -c "-$COLUMNS" | tr -d $'\n'

		imgDir="$(dirname "$imgPath")"

		attrib=''
		dirAttribPath="$imgDir/attrib.md"
		if [ -f "$dirAttribPath" ]
		then
			# sort the attrib files
			sort -u -o "$dirAttribPath" "$dirAttribPath"
			attrib="$(grep -iPo "(?<=$(quoteRe "$imgFilename")\s).+$" "$dirAttribPath" | sed 's/ \+/ /g')" || true
		fi

		# attempted to pull attribution from metadata using imagemagick but did not succeed

		# allow for initial load of attribution from the filename
		if [[ -z "$attrib" ]] && echo "$imgFilename" | grep -qiP "[-_ ]by[-_ ]"
		then
			attrib="$(echo "${imgFilename%%.*}" | sed 's/[-_]/ /g' | sed 's/\( \|^\)\w/\U&/g' | sed 's/ \(By\|And\) /\L&/g' | perl -pe 's/_[a-f0-9]{30}//g')"
			echo "$imgFilename $attrib" >> "$dirAttribPath"
		fi

		thumbnailPath="${thumbnails_dir}/${imgPath#"$path_root/"}"

		thumbnailUrl="${thumbnailPath/#"$path_root"/}"
		thumbnailUrl="${thumbnailUrl// /%20}"
		imageUrl="$raw_root${imgPath/#"$path_root"/}"
		imageUrl="${imageUrl// /%20}"

		folderReadmeUrl="$(dirname "$imgPath")/README.MD"
		folderReadmeUrl="${folderReadmeUrl#"$path_root"}"
		folderReadmeUrl="${folderReadmeUrl// /%20}"

		# imgFolderName="$(basename "$(dirname "$imgPath")")"
		imgFolderName="${imgDir#"$dir"}"
		imgFolderName="${imgFolderName#\/}"
		imgFolderPath="$imgDir" # can rename
		customHeaderID="$(echo "${imgFolderName}" | perl -pe 's/[ -_"#]+/-/g')"

		if [ -n "$attrib" ]
		then
			# strip markdown links out of the alt text
			alt_text=$(echo "$attrib" | sed 's/([^)]*)//g' | sed 's/[][]//g')
		else
			alt_text="$imgFilename"
		fi

		imgFolderPathReggie="$(quoteRe "${imgFolderPath}/")"

		imgFolderCount="$(echo "$imgFiles" | grep -iPc "$imgFolderPathReggie")"

		imgFolderHeader="## [$imgFolderName]($folderReadmeUrl) - $imgFolderCount"

		# if [[ "$dirReadmePath" == "$rootReadmePath" ]]
		# then
                #
		# fi

		# show full image for bottom level dirs
		# TODO support dirs with images at depth 1 *and* sub dirs
		if [[ "$bottomLevelDir" == 1 ]]
		then

			echo -n "[![$alt_text]($imageUrl \"$alt_text\")]($imageUrl)" >> "$dirReadmePath"

			# have to do a bunch of shenanigans to get the attribution immediately below the picture
			if [ -n "$attrib" ]
			then
				echo "\\" >> "$dirReadmePath"
				echo "$attrib" >> "$dirReadmePath"
			else
				echo >> "$dirReadmePath"
			fi
			echo >> "$dirReadmePath"

		#thumbnails only
		else

			if ! grep -qP "^$(quoteRe "${imgFolderHeader}")\$" "$dirReadmePath"
			then
				# adding an HTML anchor for persistent header links
				# since 1) github flavored markdown does not support markdown custom header ID syntax and 2) the auto headers include the file count
				echo "" >> "$dirReadmePath"
				echo "<a id=\"${customHeaderID}\"></a>" >> "$dirReadmePath"
				echo "" >> "$dirReadmePath"
				echo "${imgFolderHeader}" >> "$dirReadmePath"
			fi

			echo    "[![$alt_text]($thumbnailUrl \"$alt_text\")]($imageUrl)" >> "$dirReadmePath" 


		fi

	echo -en '\r'
	
	# if [[ "$i" -gt 50 ]]
	# then
	# 	echo "breaking early for testing"
	# 	break
	# fi

	done

	parentDirUrl="$(echo "$friendlyDirName" | sed -r 's|/[^/]+$||')"
	echo -e "\n" >> "$dirReadmePath"
	echo "[back to top](#)" >> "$dirReadmePath"
	echo "[up one level]($parentDirUrl/README.MD)" >> "$dirReadmePath"
done

# build the root table of contents
pathRootEscaped="$(quoteRe "$path_root/")"
rootDirs="$(echo "$imgFiles" | sed "s/^$pathRootEscaped//g" | grep -iPo '^[^/]+' | sort -u)"
echo "$rootDirs" | while read -r rootDir
do
	echo "- [$rootDir](/$rootDir/README.MD) - $(find-images "$path_root/$rootDir" | wc -l)" >> "$tocMD"
	# echo $'\n' >> "$tocMD"
done
tocText="$(cat "$tocMD" | sort -rn -t '-' -k3)"
rm "$tocMD"

readmeTemplate="$(cat "$readmeTemplatePath")"
readmeTemplate="${readmeTemplate/\{thumbnails\}/"$thumbnailText"}" 
readmeTemplate="${readmeTemplate/\{table of contents\}/"$tocText"}" 
readmeTemplate="${readmeTemplate/\{total\}/"$(numfmt --grouping "$totalImages")"}" 
echo "$readmeTemplate" > README.MD


# if pandoc is installed, convert the markdown files to html for easy preview and debugging
if type pandoc >/dev/null 2>&1
then
	echo "--updating readme html's..."
	mdFiles=$(find "$path_root" -maxdepth 5 -type f -iname '*.md' -not -path '*/.*' -not -iname 'attrib.md' | sort -t'/' -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 -k6,6 -k7,7)

	i=0
	total=$(echo "$mdFiles" | wc -l)

	echo "$mdFiles" | while read -r src
	do
		((i++)) || true
		descname="$(basename "$(dirname "$src")")/$(basename "$src")"
		printf '\033[2K%4d/%d: %s...' "$i" "$total" "$descname" | cut -c "-$COLUMNS" | tr -d $'\n'
		metaTitle="${src%.*}"
		metaTitle="${metaTitle#"$path_root"}"
		metaTitle="${metaTitle#/}"
		metaTitle="$(echo "$metaTitle" | sed 's|/README$||g')"
		mdDir="$(dirname "$src")"
		bottomLevelDir="$(bottom-level-dir "$mdDir")"

		if [ "${mdDir,,}" = "${path_root,,}" ]
		then
			metaTitle="Wallpapers"
		fi
		htmlPath="${src%.*}.html"
		if [ -f "$htmlPath" ]
		then
			rm "$htmlPath"
		fi
		

		htmlText=$(pandoc --from=gfm --to=html --standalone --metadata title="$metaTitle" "$src")
		htmlText="${htmlText//.md/.html}"
		htmlText="${htmlText//.MD/.html}"
		htmlText="${htmlText//"$raw_root"/}"

		echo "$htmlText" | while read -r htmlLine
		do

			# write existing line to file
			echo "$htmlLine" >> "$htmlPath"

			# only doing edits based on htmlLine on bottom level readmes
			if [[ "$bottomLevelDir" == 0 ]]
			then
				continue
			fi

			if [[ "$htmlLine" == "</header>" ]]
			then
				modText="<iframe name=\"dummyframe\" id=\"dummyframe\" style=\"display: none;\"></iframe>"
				echo "$modText" >> "$htmlPath"

			fi

			if [[ "$htmlLine" == *"href"* && "$htmlLine" == *"img src"* && "$htmlLine" != *".internals/thumbnails"* && "$htmlPath" != *"thumbnails_test"* ]]
			then
				href="$(echo "$htmlLine" | grep -iPo '(?<=href=")[^"]+' | urldecode)"
				# title=$(echo "$htmlLine" | grep -iPo '(?<=title=")[^"]+')

				renamePrefil="$(basename "$href")"
				renamePrefil="${renamePrefil%.*}"
				# TODO HTML decode this first
				if [[ -f "${path_root}/${href}" ]]
				then
					resolution=$(identify -ping -format '%wx%h' "${path_root}/${href}" 2>&1)
				else
					resolution="???"
				fi
				
				modText="
				<form action=\"/cgi-bin/move\" target=\"dummyframe\" style='width:400px'>
				<input type=\"hidden\" id=\"dirname\" name=\"dirname\" value=\"$(dirname "$href")\">
				<input type=\"hidden\" id=\"sourcename\" name=\"sourcename\" value=\"$(basename "$href")\">
				<label>${resolution}</label>
				<br>
				<label for=\"destname\">new file name:</label>
				<input type=\"text\" id=\"destname\" name=\"destname\" style='width:100%' value=\"$renamePrefil\"><br>
				<input type=\"submit\" value=\"Rename\">
				</form>
				<form action=\"/cgi-bin/trim\" target=\"dummyframe\">
				<input type=\"hidden\" id=\"dirname\" name=\"dirname\" value=\"$(dirname "$href")\">
				<input type=\"hidden\" id=\"sourcename\" name=\"sourcename\" value=\"$(basename "$href")\">
				<input type=\"submit\" value=\"Trim\">
				</form>
				<br>
				"

				# write new stuff to file
				echo "$modText" >> "$htmlPath"

			fi


		done

		# make sure images don't blow out the page
		sed -i '12i img {max-width: 100%;	height: auto;}' "$htmlPath"
		# remove that double header
		perl -i -00pe 's|<header.+?title-block-header.+?</header>||gs' "$htmlPath"

		echo -en "\r"

	done
fi

echo ""

echo "done at $(date)"
