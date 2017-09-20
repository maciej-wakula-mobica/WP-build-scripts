#!/bin/bash
SRC="${HOME}/src/WorldPay/rpc-agent"
GIT_CORE_GO="https://github.com/wptechinnovation/wpw-sdk-go.git"
CORE_PATH="${SRC}/src/github.com/wptechinnovation/wpw-sdk-go"
RPCSRC="${CORE_PATH}/applications/rpc-agent"
GIT_THRIFT_DEFS="https://github.com/wptechinnovation/wpw-sdk-thrift.git"
THRIFT_DEFS_PATH="${SRC}/wpw-sdk-thrift/rpc-thrift-src"
THRIFT_GO_PKG_PREFIX="github.com/wptechinnovation/wpw-sdk-go/wpwithin/rpc/wpthrift/gen-go/"

GOPATH=""
DO_CLEANUP='n'  # Clean build from scratch
DO_GET='y'  # Create dirs (if needed) and fetch sources
DO_INSTALL='y'  # Try to inastall compiled binaries
DO_SDK='y'  # Generate SDK thrift sources
BUILD_SDK_LIST='node,java,go,python2,cs'  # SDK thrift sources  to generate
VER="TestVersion"  # Version name of rpc-agent to build

EXEC_THRIFT='thrift'
OPT_ERASE='n'
PRESTART_STR=''
POSTSTART_STR=''
PREEND_STR=''
POSTEND_STR=''
PREMSG_STR=''
POSTMSG_STR=''
CURRENT_STEP=''
STEP_MSG=''

set -e # Exit on any error
set -u
#set -v
#set -x

# Parse CLI
while [[ "${#}" -gt 0 ]] ; do
	case "${1}" in
	--gopath)
		shift 1
		GOPATH="${GOPATH}:${1}"
		;;
	--cleanup)
		DO_CLEANUP='y'
		;;
	--no-cleanup)
		DO_CLEANUP='n'
		;;
	--get|--fetch)
		DO_GET='y'
		;;
	--no-get|--no-fetch)
		DO_GET='n'
		;;
	--install)
		SO_INSTALL='y'
		;;
	--no-install)
		DO_INSTALL='n'
		;;
	--build-sdk)
		DO_SDK='y'
		;;
	--thrift-exec)
		shift 1
		EXEC_THRIFT="${1}"
		;;
	--travis-mark-steps)
		OPT_ERASE='y'
		PRESTART_STR=`echo -n -e "travis_fold:start:"`
		#POSTSTART_STR=`echo -n -e "\n\e[0K"`
		POSTSTART_STR=`echo -n -e "\n"`
		#PREMSG_STR=`echo -n -e "\e[0K\e[33;1m"`
		PREMSG_STR=`echo -n -e "\e[0K\e[44;1m"`
		POSTMSG_STR=`echo -n -e "\e[0m\n"`
		PREEND_STR=`echo -n -e "travis_fold:end:"`
		POSTEND_STR=`echo -n -e "\n\e[0K"`
		;;
	--help)
		echo "Usage: ${0} [options]"
		echo "Example: ${0} --cleanup --get --install --build-sdk"
		echo "Options:"
		echo "  --gopath '/path/to/add"
		echo "    Adds path to the GOPATH"
		echo "  --cleanup / --no-cleanup"
		echo "    Do (or not) clean build"
		echo "  --get / --no-get"
		echo "    Get (or not) sources from the repo"
		echo "  --install / --no-install"
		echo "    Install (or not) the compiled binaries"
		echo "  --build-sdk"
		echo "    Build (or not) the sdk thrift sources"
		echo "  --thrift-exec '/path/to/thrift'"
		echo "    Provide custom path to thrift executable"
		exit 0
		;;
	*)
		echo "use '${0} --help'"
		exit 1
		;;
	esac
	shift 1
done


function Section {
	OLD_STEP="${CURRENT_STEP}"
	STEP_MSG="${1}"
	CURRENT_STEP=$(echo "${1}"|sed 's/ /_/g'|sed 's/[^A-Za-z_]/./g')
	[[ "${OPT_ERASE}" == n ]] && return
	# Close old section
	[[ -n "${OLD_STEP}" ]] && {
		echo -n "${PREEND_STR}${OLD_STEP}${POSTEND_STR}"
	}
	# Init new section
	[[ -n "${CURRENT_STEP}" ]] && {
		echo -n "${PRESTART_STR}${CURRENT_STEP}${POSTSTART_STR}";
		echo -n "${PREMSG_STR}${STEP_MSG}${POSTMSG_STR}"
	}
}

# Just ensure that required binaries are present on the system
#TODO echo "Checking for 'id'" && id -u >/dev/null
Section "Checking for dependencies"
which ${EXEC_THRIFT} || { echo "No 'thrift' executable in PATH"; exit 1; }  # Potentially unsafe
which git || { echo "No 'git' in PATH" >&2; exit 1; }
which sh || { echo "No 'sh' in PATH" >&2; exit 1; }
which go || { echo "No 'gi' in PATH" >&2; exit 1; }
which id || { echo "No 'id' in PATH... missing coreutils?" >&2; exit 1; }
which rm || { echo "No 'rm' in PATH... missing coreutils?" >&2; exit 1; }
which mkdir || { echo "No 'mkdir' in PATH... missing coreutils?" >&2; exit 1; }
which date || { echo "WARNING: No 'date' in PATH thus build might fail to fetch current date for the build" >&2; }
which zip || { echo "WARNING: No 'zip' in PATH thus build might encounter errors" >&2; }
which tar || { echo "WARNING: No 'tar' in PATH thus build might encounter errors" >&2; }
echo "all OK."

# TODO: Fetch thrift exec

[[ `id -u` -eq 0 ]] && {
	echo "Do NOT run as root"
	exit 1
}

# CLEANUP before doing anything
if [[ "${DO_CLEANUP}" == y ]] ; then
	Section "Performing cleanup"
	rm -rf "${SRC}"
	cd "${SRC}"
fi

# Clone or update sources
if [[ "${DO_GET}" == y ]] ; then
	Section "Fetching sources ..."
	mkdir -p "${SRC}/src"
	cd "${SRC}"
	export GOPATH="${PWD}"
	### WPW CORE GO
	
	# TODO: Check if GOPATH contains CORE_PATH
	mkdir -p "${CORE_PATH%/*}"
	cd "${CORE_PATH%/*}"
	if [[ -d "${CORE_PATH}" ]] ; then
		cd "${CORE_PATH}"
		git pull
		git submodule update
	else
		mkdir -p "${CORE_PATH}"
		# Use recursive clone to fetch submodules
		git clone --recursive "${GIT_CORE_GO}"
	fi
	
	cd "${SRC}"
	go get git.apache.org/thrift.git/lib/go/thrift/...
	echo "Using workaround for non-working thrift v11"
	{
		cd "${SRC}/src/git.apache.org/thrift.git"
		git checkout 0.10.0
		cd -
	}

	# Use thrift to generate sources
	cd "${SRC}"
	if [[ -d "${THRIFT_DEFS_PATH}" ]] ; then
		cd "${THRIFT_DEFS_PATH}"
		git pull
	else
		git clone "${GIT_THRIFT_DEFS}"
	fi
fi
# UPDATE TODO
# DONE

cd "${THRIFT_DEFS_PATH}"
rm -rf gen-go
rm -rf "${SRC}/src/${THRIFT_GO_PKG_PREFIX}"
${EXEC_THRIFT} -r --gen go:package_prefix="${THRIFT_GO_PKG_PREFIX}" wpwithin.thrift
if [[ "${DO_SDK}" == 'y' ]] ; then
	Section "Generating thrift sources for SDK"
	if [[ ",${BUILD_SDK_LIST}," == *,node,* ]] ; then
		${EXEC_THRIFT} -r --gen js:node wpwithin.thrift
		#cp -rf gen-nodejs "${SRC}/src/${THRIFT_GO_PKG_PREFIX%/}"
	fi
	if [[ ",${BUILD_SDK_LIST}," == *,python2,* ]] ; then
		${EXEC_THRIFT} -r --gen py wpwithin.thrift
	fi
	#if [[ ",${BUILD_SDK_LIST}," == *,go,* ]] ; then
	#	thrift -r --gen go:node wpwithin.thrift
	#fi
	if [[ ",${BUILD_SDK_LIST}," == *,cs,* ]] ; then
		${EXEC_THRIFT} -r --gen csharp:nullable wpwithin.thrift
	fi
	if [[ ",${BUILD_SDK_LIST}," == *,java,* ]] ; then
		${EXEC_THRIFT} -r --gen java wpwithin.thrift
	fi
fi
mv -f gen-go "${SRC}/src/${THRIFT_GO_PKG_PREFIX%/}"


Section "Build rps-agents"
cd "${RPCSRC}"
go get .
sh build-all.sh -v${VER}

if [[ "${DO_INSTALL}" == 'y' ]] ; then
	Section "Generate thrift for SDKs"
	if [[ -n "${WPW_HOME:=}" && -d "${WPW_HOME}" ]] ; then
		mkdir -p "${WPW_HOME}"
		cp build/* "${WPW_HOME}/"
	else
		echo "Cannot install as WPW_HOME is not set" >&2
	fi
fi

Section
exit 0
