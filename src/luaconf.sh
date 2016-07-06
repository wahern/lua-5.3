#!/bin/sh
set -e # strict error
set -u # don't expand unbound variable
set -f # disable pathname expansion
set -C # noclobber

unset IFS
export LC_ALL=C

# default list of luaconf.h variables to substitute
LUACONF_SUBST="LUA_ROOT LUA_LDIR LUA_CDIR"

# variables which require a trailing slash
LUACONF_SLASH_NOT_REQUIRED=""
LUACONF_SLASH_REQUIRED="*"

# print formatted string
warn() {
	printf "%s: %.0s${1}\n" "${0##*/}" "$@" >&2
}

panic() {
	warn "$@"
	exit 1
}

# test whether variable is defined
isset() {
	eval "[ \"\${$1+yes}\" = \"yes\" ]"
}

# test whether a variable requires a trailing slash using glob pattern
ismatch() {
	# test whether pattern consumes all of string
	[ "${1##${2}}" = "" ]
}

# test whether a trailing slash is required for a variable
slash_required() {
	for slash_required_P in $LUACONF_SLASH_NOT_REQUIRED; do
		[ ${#slash_required_P} -gt 0 ] || continue
		! ismatch "$1" "$slash_required_P" || return 1
	done

	for slash_required_P in $LUACONF_SLASH_REQUIRED; do
		[ ${#slash_required_P} -gt 0 ] || continue
		! ismatch "$1" "$slash_required_P" || return 0
	done

	return 1
}

# unescape backslash-escaped string
unescape() {
	IFS=
	eval "${1}=\"\$(printf \"%bx\" "\${${1}}")\""
	eval "${1}=\${${1}%x}"
	unset IFS
}

# determine if string was word-split (trailing backslash)
iswordsplit() {
	iswordsplit_N=0
	iswordsplit_S="${1}"
	while [ "${iswordsplit_S%\\}" != "${iswordsplit_S}" ]; do
		iswordsplit_S="${iswordsplit_S%\\}"
		iswordsplit_N=$((${iswordsplit_N} + 1))
	done

	# was word-split if odd number of trailing backslashes
	[ $((${iswordsplit_N} % 2)) -eq 1 ];
}

# read MAKEFLAGS macro NAME and assign to VAR, returning true if macro was
# defined, false otherwise
import_makeflag() {
	import_makeflag_NAME="${1}"
	import_makeflag_VAR="${2:-${1}}"

	IFS=" " # exclude tab so we don't confuse with space when unescaping
	set -- ${MAKEFLAGS:-}
	unset IFS

	while [ $# -gt 0 ]; do
		# skip non-K=V pairs
		if [ "${1#*=}" = "${1}" ]; then
			shift 1
			continue
		fi

		# load K=V pair
		import_makeflag_K="${1%%=*}"
		import_makeflag_V="${1#*=}"

		shift 1

		# keep reading if V is word-split
		while iswordsplit "${import_makeflag_V}"; do
			[ $# -gt 0 ] || break;
			import_makeflag_V="${import_makeflag_V%\\}"
			import_makeflag_V="${import_makeflag_V} ${1}"
			shift 1
		done

		# skip if not the macro we're looking for
		[ "${import_makeflag_NAME}" = "${import_makeflag_K}" ] || continue

		# decode backslash-escaping
		unescape import_makeflag_V

		eval "${import_makeflag_VAR}=\${import_makeflag_V}"

		return 0
	done

	# not found
	return 1
}

# for each variable specified, call import_makeflag unless already defined
import_makeflags() {
	for import_makeflags_K; do
		! isset "$import_makeflags_K" || continue
		import_makeflag "$import_makeflags_K" || :
	done
}

# process -D option
define() {
	IFS="="
	set -- $1
	unset IFS

	eval "$1=${2-1}"
}

# process -U option
undefine() {
	unset $1
}

# process -x option
exclude() {
	exclude_NAME="$1"
	exclude_LUACONF_SUBST=
	set -- $LUACONF_SUBST
	for K; do
		[ "$K" != "$exclude_NAME" ] || continue
		exclude_LUACONF_SUBST="$exclude_LUACONF_SUBST $K"
	done
	LUACONF_SUBST="$exclude_LUACONF_SUBST"
}

USAGE_SHORTOPTS="D:U:x:h"

usage() {
	cat <<-EOF
	Usage: ${0##*/} [-$USAGE_SHORTOPTS]
	  -D NAME=VALUE  define variable
	  -U NAME        undefine variable
	  -x NAME        exclude variable from substitution
	  -h             print this usage message

	Report bugs to <william@25thandClement.com>
	EOF
}

while getopts "$USAGE_SHORTOPTS" OPTC; do
	case $OPTC in
	D)
		define "$OPTARG"
		;;
	U)
		undefine "$OPTARG"
		;;
	x)
		exclude "$OPTARG"
		;;
	h)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 1
		;;
	esac
done

shift $(($OPTIND - 1))
if [ $# -gt 0 ]; then
	warn "%s: unknown command" "$1"
	usage >&2
	exit 1
fi

# default Makefile path variables
import_makeflags V INSTALL_TOP INSTALL_LMOD INSTALL_CMOD
: ${V:=5.3}
: ${INSTALL_TOP:=/usr/local}
: ${INSTALL_LMOD:=${INSTALL_TOP}/share/lua/${V}}
: ${INSTALL_CMOD:=${INSTALL_TOP}/lib/lua/${V}}

# default luaconf.h path variables
import_makeflags LUA_ROOT LUA_LDIR LUA_CDIR
: ${LUA_ROOT:=${INSTALL_TOP}}
: ${LUA_LDIR:=${INSTALL_LMOD}}
: ${LUA_CDIR:=${INSTALL_CMOD}}

# build sed command
set -- sed
TAB="$(printf "\t")"
for K in ${LUACONF_SUBST}; do
	isset "$K" || continue
	if slash_required "$K"; then
		eval V=\"\${$K%/}/\"
	else
		eval V=\"\${$K}\"
	fi
	set -- "$@" -e "s#^\#define $K[$TAB ].*#\#define $K$TAB\"${V}\"#"
done

exec "$@"
