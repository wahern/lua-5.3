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
: ${V:=5.3}
: ${INSTALL_TOP:=/usr/local}
: ${INSTALL_LMOD:=${INSTALL_TOP}/share/lua/${V}}
: ${INSTALL_CMOD:=${INSTALL_TOP}/lib/lua/${V}}

# default luaconf.h path variables
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
