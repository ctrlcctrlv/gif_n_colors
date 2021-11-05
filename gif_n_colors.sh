#!/bin/bash
if [ ! -z $DEBUG ]; then set -x; fi
function green_str {
local green=$(tput setaf 2)
local reset=$(tput sgr0)
RET=$green"$@"$reset
}
function green_echo {
green_str "$@"
echo $ECHO_ARGS "$RET"
}
function truthy { val="$1" ; _truthy() { return $( [[ ${val,,} = $2 ]] ) ;} ; return $(_truthy "$val" 'on' || _truthy "$val" 'true' || _truthy "$val" '1') ;}
function exit {
	cleanup;
	set +x;
	[[ ! -z "$2" && "$2" != "1" ]] && >&2 echo `basename -s.sh $0`: Error: "$2"
	[[ $1 -ne 0 && ! ($2 -eq 1 || $3 -eq 1) ]] && usage
	unset exit
	exit $1
}
trap "exit 1 'Signal caught, exiting…'" INT

function usage {
>&2 cat << EOF
USAGE: gif_n_colors [<INPUT>] [<OUTPUT>] [-d] [FLAGS]
EOF
}

function usage_long {
usage;
>&2 cat << EOF
OPTIONS:
-n [int] … number of colors
-e, --despeckle-strength [int] … speckles can consist of n joined pixels of same color

FLAGS:
-d, --despeckle
-D, --dither
--no-cleanup … keep all temporary files

If <INPUT> not provided, will read from STDIN.
EOF
}

TO_CLEANUP=()
CLEANUP_NAMES=()
RM=`which rm`
TMPDIR=$(dirname $(mktemp -u))
function cleanup {
if [ ! -z $DEBUG_CLEANUP ]; then FINDARGSEXTRA=('-printf' "%p "); fi
if truthy "$NO_CLEANUP"; then return 1; fi
TC_LEN=${#TO_CLEANUP[@]}
for (( i=0; i<${TC_LEN}; i++ )); do
	if [ ! -z "$DEBUG_CLEANUP" ]; then green_str "Checking ${CLEANUP_NAMES[$i]}…" && >&2 printf "$RET"; fi
	NL=$(FIND=`find "$TMPDIR" -type d '(' '!' -readable -prune -o -true ')' -o -type f -readable -iwholename "${TO_CLEANUP[$i]}*" "${FINDARGSEXTRA[@]}" -exec "$RM" {} +;` && printf "$FIND" || printf true)
	if [ ! -z "$DEBUG_CLEANUP" ]; then if ! truthy "$NL"; then echo "$NL"; else >&2 echo; fi; fi
done
}

function cleaned_up_file {
local F
F=`mktemp $2`; TO_CLEANUP+=("$F"); CLEANUP_NAMES+=("$1")
eval $1="$F"
}

cleaned_up_file CMAP
cleaned_up_file TEMP -u
cleaned_up_file TEMP2 -u
DESPECKLE_STR=2
NCOLORS=8

function isint { (( 10#$1 )) 2>/dev/null ;}
function int_or { eval isint '$'"$1"_V && eval "$1"='$'"$1"_V; eval unset $1_V ;}
function file_ok() { return `test -f "$1" && test -s "$1" && test -r "$1"`; }

while true; do
	case "$1" in
		--no-cleanup) NO_CLEANUP=true; shift;;
		-n|--ncolors) NCOLORS_V="$2"; int_or NCOLORS; shift 2;;
		-d|--despeckle) DESPECKLE=true; shift;;
		-D|--dither) DITHER=true; shift;;
		-e|--despeckle-strength) DESPECKLE_STR_V="$2"; int_or DESPECKLE_STR; shift 2;;
		-o|--output) OUT="$2"; shift 2;;
		-h|--help|-u|--usage|-H) usage_long; exit 1 1;;
		'') if [[ -z $OUT ]]; then OUT=`mktemp -u`.gif; fi; break;;
		*) if [[ ! -z $OUT ]]; then exit 1 'Cannot process multiple I/O pairs at a time'; else if [[ -z $IN ]]; then IN="$1"; else OUT="$1"; fi; fi; shift;;
	esac
done

DESPECKLE_STR=$((DESPECKLE_STR*2))
if ! file_ok "$IN"; then
	cleaned_up_file IN --suffix=.gif
	RVALUE=$(tee "$IN")
	if [[ -z "$RVALUE" ]]; then exit 1; fi
fi

>&2 green_echo Doing cmap step…
if truthy "$DITHER"; then DITHER_ARGS=$('-dither' 'FloydSteinberg'); fi
convert "$IN" '(' -clone 0--1 -append -colors "$NCOLORS" ${DITHER_ARGS[@]} -write "$CMAP" ')' -map "$CMAP" "$TEMP".gif

if truthy "$DESPECKLE"; then mv "$TEMP".gif "$OUT" && echo "$OUT"; exit 0; fi

>&2 green_echo '(Despeckle)' Coalescing animation to frames…
convert "$TEMP".gif -coalesce "$TEMP-%03d.png"

>&2 green_echo '(Despeckle)' Removing speckles…
ls "$TEMP"*png | parallel --bar "convert {} '(' -clone 0--1 -define connected-components:mean-color=true -define connected-components:area-threshold=$DESPECKLE_STR -connected-components 8 ')' -composite $TEMP2"_'`'python -c \''print("{:05d}".format({#}))'\''`'.png

>&2 green_echo '(Despeckle)' Joining `ls "$TEMP"*png | wc -l` frames…
convert -delay 10 "$TEMP2"* "$OUT"

echo "$OUT"
exit 0
