#!/usr/bin/env bash
#
# rancher launch script
# Configures proxy, kubernetes version for foresight developers
#

function Usage {
	local NAME=$1
	local ERR=$2
	local RDCTL=${RDCTL:-rdctl}

	cat <<-EoM

	${NAME}: rancher-desktop control and configuration with appropriate proxy configuration.

	Usage: ${NAME} command [options]

	Commands:
		setup [options] - configure rancher-desktop options.
		start|run|go    - start rancher-desktop.
		stop|shutdown   - stop rancher-desktop.
		restart         - stop, then start rancher-desktop.
		shell           - open a rancher-desktop shell.
		status          - check rancher-desktop VM status
		settings        - print settings.
		snapshot        - save a network config snapshot.
		clearlogs       - clear down all logfiles.
		logs            - print logfile location.
		k8s-reset       - reset kubernetes to clean post-install state.
		factory-reset   - reset rancher-desktop to factory defaults.
		version         - print rancher-desktop version.
		help            - print this help, open the wiki, and exit.

	Kubernetes option applies to 'setup' only:
		-k|-k8s|-kubernetes {version} - configure kubernetes with the given version.
		To disable kubernetes, specify 'disabled|false|off|no|0'

	Proxy options apply to 'setup/start/restart':
		-p|-proxy|-o|-office        - configure with proxy enabled (for working in-office).
		-n|-noproxy|-r|-remote|-vpn - configure without proxy (for working remotely).
		Default is auto-selected based on current WiFi network name.

	Other options:
		-x|-debug - enable script debugging output.

	Notes:
	1. More advanced commands are available by running '${RDCTL}' directly.
	2. Please run '${NAME} setup' at least once to configure the correct options.
	3. Help wiki: ${RD_WIKI}
	EoM

	if [[ ${ERR} -ge 2 ]] ; then
		openUrl "${RD_WIKI}"
	fi
}

# open the users' web browser at the given URL
# See MacOS /usr/bin/open (1)
function openUrl {
	local URL="${1}"
	echo -e "\nOpening URL: [${URL}]"
	/usr/bin/open "${URL}"
}


# Take a snapshot of network configuration, processes etc. for diagnostic purposes.
function configSnapshot {
	local LOGDIR="$1"
	local NOW=$(date +'%Y%m%d_%H%M%S')
	local LOGFILE="${LOGDIR}/snapshot-${NOW}.log"
	echo "rancher-desktop config snapshot - ${NOW}" >${LOGFILE}
	showRancherStatus >>${LOGFILE} 2>&1
	echo -e "\n--------\nrdctl list-settings\n" >>${LOGFILE}
	${RDCTL} list-settings >>${LOGFILE} 2>&1
	echo -e "\n--------\nifconfig\n" >>${LOGFILE}
	ifconfig -a >>${LOGFILE}
	echo -e "\n--------\nnetstat\n" >>${LOGFILE}
	netstat -rn >>${LOGFILE}
	echo -e "\n--------\nps -ef\n" >>${LOGFILE}
	ps -ef >>${LOGFILE}
	echo "Snapshot ${NOW} saved to ${LOGFILE}"
}

# Clear the log files. Rancher should ideally be in a stopped state.
function clearLogs {
	local LOGDIR="$1"
	local LIMADIR
	local LF

	if pushd "${LOGDIR}" >/dev/null ; then
		echo "clearing logs in: ${LOGDIR}"
		for LF in *.log ; do
			if [[ -s ${LF} ]] ; then
				case ${LF} in
					snapshot-*) ;;
					*) >${LF} ; echo ${LF} ;;
				esac
			fi
		done
		popd >/dev/null
	fi

	LIMADIR=$(getLimaNetworksLogDir "${LOGDIR}")
	if [[ -n "${LIMADIR}" ]] ; then
		if pushd "${LIMADIR}" >/dev/null ; then
			echo "clearing logs in: ${LIMADIR}"
			for LF in *.log ; do
				if [[ -s ${LF} ]] ; then
					>${LF}
					echo ${LF}
				fi
			done
			popd >/dev/null
		fi
	fi
}

# Print the locations of the rancher and lima logs
function showLogDir {
	local LOGDIR="$1"
	local LIMADIR

	echo -e "rancher-desktop logs are in:\n${LOGDIR}"
	LIMADIR=$(getLimaNetworksLogDir "${LOGDIR}")
	if [[ -n "${LIMADIR}" ]] ; then
		echo -e "\nlima network logs are in:\n${LIMADIR}"
	fi
}

# return the location of the lima VM network logs
function getLimaNetworksLogDir {
	local LOGDIR="$1"
	local LIMADIR

	for LF in "${LOGDIR}"/*.log ; do
		if [[ -L "${LF}" ]] ; then
			LIMADIR=$(readlink -f "${LF}")
			echo "${LIMADIR%/*/*}/_networks"
			break
		fi
	done
}

# Configure the rancher-desktop proxy as requested
# If it's already configured correctly, don't change it.
function configureRancherDesktopProxy {
	local USE_PROXY=$1
	local NET_LOCATION=$(getNetworkLocation)
	local PROXY_STATUS=( $(getRancherDesktopProxyConfig) )

	if [[ ${USE_PROXY} -ge 1 ]] ; then
		if [[ !( ${PROXY_STATUS[1]} =~ office ) ]] ; then
			configureProxy "${RD_OVERRIDE_YAML}" ${USE_PROXY}
			if [[ ${NET_LOCATION} != "OFFICE" ]] ; then
				log "WARNING: Using PROXY configuration whilst on ${NET_LOCATION} network - this is probably wrong!"
				sleep 5
			fi
		fi
	else
		if [[ !( ${PROXY_STATUS[1]} =~ remote ) ]] ; then
			configureProxy "${RD_OVERRIDE_YAML}" ${USE_PROXY}
			if [[ ${NET_LOCATION} != "REMOTE" ]] ; then
				log "WARNING: Using NO-PROXY configuration whilst on ${NET_LOCATION} network - this is probably wrong!"
				sleep 5
			fi
		fi
	fi

	PROXY_STATUS=( $(getRancherDesktopProxyConfig) )
	log "Rancher configured for proxy: ${PROXY_STATUS[*]} [network: ${NET_LOCATION}]"
}

# Return (print) an array (statue, name, description) describing proxy status.
function getRancherDesktopProxyConfig {
	local PROXY='UNCONFIGURED'
	local DESC

	if [[ -r "${RD_OVERRIDE_YAML}" ]] ; then
		PROXY=$(awk '/^#-%proxy:/ { print $2 }' "${RD_OVERRIDE_YAML}")
	fi

	if [[ -z ${PROXY} || ${PROXY} == "0" ]] ; then
		DESC=("OFF" "remote/vpn" "-")
	elif [[ ${PROXY} =~ UNCONFIGURED ]] ; then
		DESC=("OFF" "UNCONFIGURED" "-")
	else
		DESC=("ON" "in-office" "${APP_PROXY}")
	fi

	echo "${DESC[*]}"
}

# Configure proxy and other settings internal to the Lima VM
function configureProxy {
	local OVERRIDE_YAML="$1"
	local USE_PROXY="${2:-0}"
	configureOverrides "${OVERRIDE_YAML}" ${USE_PROXY} "${APP_PROXY}" "${APP_NO_PROXY}"
}

# Set/clear proxy variables for NodeJS (the rancher UI) in the current shell environment
# Unset other proxy env variables so they can't leak into the LimaVM, which causes other issues.
function configureNodeJSProxy {
	local USE_PROXY=$1
	unset all_proxy ALL_PROXY # causes trouble+confusion
	unset npm_config_http_proxy npm_config_https_proxy npm_config_proxy
	unset NPM_CONFIG_HTTP_PROXY NPM_CONFIG_HTTPS_PROXY NPM_CONFIG_PROXY
	unset http_proxy https_proxy no_proxy
	unset HTTP_PROXY HTTPS_PROXY NO_PROXY
	if [[ ${USE_PROXY} -ge 1 ]] ; then
		npm_config_proxy="${APP_PROXY}"
		no_proxy="${APP_NO_PROXY}"
		export npm_config_proxy no_proxy
	fi
}

# Configure startup scripts for services within the Lima VM
# Sets proxy, logfile location and installs internal certificates
function configureOverrides {
	local OVERRIDE_YAML="$1"
	local USE_PROXY="$2"
	local PROXY="$3"
	local NO_PROXY="$4"

	local PROXY_SH="/etc/profile.d/proxy.sh"
	local INITD="/etc/init.d"
	local CONFD="/etc/conf.d"
	local BLK_SETUP_SH="/var/lib/misc/blk-setup.sh"
	local BLK_PROVISIONING_INFO="Added by BlackRock Foresight rancher script: $(date)"
	local SETUP_MARK='###-BLK-RANCHER-SETUP-###'

	local CONFIG_DIR=$(dirname "${OVERRIDE_YAML}")
	if [[ ! -d "${CONFIG_DIR}" ]] ; then
		# In case first-time launch has not been done
		mkdir -p "${CONFIG_DIR}"
	fi
	echo "Creating provisioning config: ${OVERRIDE_YAML}"

	local PROXY_FLAG=0
	[[ ${USE_PROXY} -ge 1 ]] && PROXY_FLAG=${PROXY}

	# Note 1: *IMPORTANT* indentation of yaml below must be <tab><4-spaces> *IMPORTANT*
	# Note 2: configure environment for dockerd and containerd
	# /etc/profile.d/*.sh files are loaded for all login shells
	# /etc/init.d/docker explicitly loads /etc/profile.d/proxy.sh at startup
	# But we want proxy set on dockerd, containerd only, hence also update /etc/init.d files.
	cat <<-EoM >"${OVERRIDE_YAML}"
	#-%proxy: ${PROXY_FLAG}
	# ${BLK_PROVISIONING_INFO}
	#
	# Enable SSH agent forwarding, refs:
	# - https://github.com/rancher-sandbox/rancher-desktop/issues/4136
	# - https://github.com/rancher-sandbox/rancher-desktop/issues/3042
	ssh:
	  forwardAgent: true
	#
	# Add values to /etc/environment, these are loaded by PAM in login shells
	env:
	  # Set BLK proxy env values
	  BLK_PROXY: '"${PROXY}"'
	  BLK_NO_PROXY: '"${NO_PROXY}"'
	  BLK_USE_PROXY: '${USE_PROXY}'
	  #
	  # Placeholder for logfile location
	  RD_LOG_DIR: '"${RD_LOGS}"'
	  #
	  # Get more info out of k3s
	  K3S_EXEC: '"--alsologtostderr --debug"'
	#
	#
	# Scripts to configure proxy, log locations etc.
	provision:
	#
	# Delete http_proxy etc. variables that may have leaked into /etc/environment
	- mode: system
	  script: |
	    #!/bin/sh
	    # Remove any HTTP_PROXY etc. variables which may have leaked in
	    sed -i -E -e '/^(ALL|all|HTTPS?|https?|NO|no)_(PROXY|proxy)=/d' /etc/environment
	#
	# BLK_SETUP script sets proxy, logfile variables for certain daemons
	- mode: system
	  script: |
	    #!/bin/sh
	    #
	    cat <<'%%%EoF%%%' >${BLK_SETUP_SH}
	    #!/bin/sh
	    # ${BLK_PROVISIONING_INFO}
	    #
	    # Conditionally set HTTP_PROXY based on BLK_USE_PROXY=1
	    if [ -z \${BLK_USE_PROXY} ] ; then
	        source /etc/environment
	    fi
	    unset all_proxy http_proxy https_proxy no_proxy
	    unset ALL_PROXY HTTP_PROXY HTTPS_PROXY NO_PROXY
	    if [ \${BLK_USE_PROXY} -ge 1 ] ; then
	        # Set HTTP proxy for outbound requests
	        http_proxy="\${BLK_PROXY}"
	        https_proxy="\${BLK_PROXY}"
	        no_proxy="\${BLK_NO_PROXY}"
	        export http_proxy https_proxy no_proxy
	        HTTP_PROXY="\${BLK_PROXY}"
	        HTTPS_PROXY="\${BLK_PROXY}"
	        NO_PROXY="\${BLK_NO_PROXY}"
	        export HTTP_PROXY HTTPS_PROXY NO_PROXY
	    fi
	    #
	    # Override log locations which otherwise default to /var/log
	    # dockerd
	    #DOCKER_LOGFILE="\${RD_LOG_DIR}/\${RC_SVCNAME}.log"
	    #LOGPROXY_LOG_DIRECTORY="\${RD_LOG_DIR}"
	    # containerd
	    log_file="\${RD_LOG_DIR}/containerd.log"
	    #
	    %%%EoF%%%
	    #
	    # source BLK_SETUP script from top of selected init scripts if not already present
	    BLK_SETUP_SED="1 a source ${BLK_SETUP_SH} # ${SETUP_MARK}"
	    for INIFILE in ${INITD}/docker ${CONFD}/containerd ; do
	        grep -q "${SETUP_MARK}" \${INIFILE} || sed -i -E -e "\${BLK_SETUP_SED}" \${INIFILE}
	    done
	#
	# Install Blackrock internal certificates into VM certificate store
	- mode: system
	  script: |
	    #!/bin/sh
	    # Fetch Blackrock internal certificate bundle, split and install into VM certificate store
	    BLK_CA_BUNDLE=/tmp/blk-ca-bundle.pem
	    if [ ! -f \${BLK_CA_BUNDLE} ] ; then
	        wget -Y off -T 5 -O \${BLK_CA_BUNDLE} https://puppet-yum.bfm.com/packages/3rd_party/certs/ca/corpcert.cer
	        awk -v PX='/tmp/blk-cert-' -v SX='.crt' 'BEGIN {cn=0;} { print > PX cn SX} /-END CERTIFICATE-/ { cn++ }' \${BLK_CA_BUNDLE}
	        mv /tmp/blk-cert-*.crt /usr/local/share/ca-certificates/
	        update-ca-certificates
	    fi
	#
	# Ensure sufficient inotify resources for foresight
	# Ref: https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
	- mode: system
	  script: |
	    #!/bin/sh
	    sysctl -w fs.inotify.max_user_watches=524288
	    sysctl -w fs.inotify.max_user_instances=512
	#
	# EoF
	EoM
}

# Warn about any expired certificates within the MacOS system keychain
function checkSystemCertificatesValidity {
	local CERT_TMPDIR=/tmp/certs.$$
	local ALL_CERTS=all-certs.pem
	local CERT
	local CERT_INFO
	local CERT_WARNINGS=0

	echo "Checking system certificates for validity..."
	mkdir -p ${CERT_TMPDIR}
	pushd ${CERT_TMPDIR} >/dev/null
	/usr/bin/security find-certificate -a -p >${ALL_CERTS}
	awk -v PX='cert-' -v SX='.crt' 'BEGIN {cn=0;} { fn=sprintf("%s%s%s",PX,cn,SX); print >fn} /-END CERTIFICATE-/ { cn++ }' ${ALL_CERTS}
	for CERT in cert-*.crt ; do
		CERT_INFO=$(openssl x509 -subject -issuer -dates -checkend 0 -noout -in ${CERT})
		if [[ $? -gt 0 ]]; then
			(( CERT_WARNINGS += 1 ))
			echo -e "WARNING: Expired certificate:\n${CERT_INFO}"
		fi
	done
	if [[ ${CERT_WARNINGS} -gt 0 ]] ; then
		echo "WARNING: rancher-desktop may raise startup errors due to expired certificates."
		echo "You may wish to stop and remove them using Keychain Access.app."
		echo "Continuing in 5 seconds..."
		sleep 5
	else
		echo "Certificates OK."
	fi
	popd >/dev/null
	[[ -d ${CERT_TMPDIR} ]] && rm -r ${CERT_TMPDIR}
}

# Configure NodeJS to use the internal certificate chain so that RD can download kubernetes in-office.
# (No idea why it doesn't find it in the MacOS keychain like everything else)
function setupBLKCertificateChain {
	local BLK_CA_CHAIN="blk-ca-chain.pem"

	if [[ ! -f "${RD_CACHE}/${BLK_CA_CHAIN}" ]] ; then
		echo "Downloading BLK certificate chain..."
		mkdir -p ${RD_CACHE}
		curl --progress-bar --output "${RD_CACHE}/${BLK_CA_CHAIN}" 'https://puppet-yum.bfm.com/packages/3rd_party/certs/ca/corpcert.cer'
	fi
	export NODE_EXTRA_CA_CERTS="${RD_CACHE}/${BLK_CA_CHAIN}"
	# If really stuck, uncomment this, but not ideal...
	export NODE_TLS_REJECT_UNAUTHORIZED=0
}

# Warn if docker.sock exists and is not writable
function checkDockerSock {
	local DS=/private/var/run/docker.sock
	local LT
	if [[ -L ${DS} ]] ; then
		LT=$(readlink -f ${DS})
		echo "checkDockerSock WARNING: ${DS} -> ${LT}"
		if [[ ${LT} =~ /.docker/ ]] ; then
			echo "checkDockerSock FATAL: Found ${DS} -> ${LT} probably left over from docker-desktop."
			echo "You need to remove this ('sudo rm ${DS}') for rancher-desktop to start successfully."
			return 1
		fi
	fi
}

# Configure rancher VM defaults, with proxy for office/remote
function setupRancherDesktop {
	local USE_PROXY=$1
	local RD_HELP_TEXT RD_ARG RD_VALID_ARGS

	# Set/unset proxy in the environment for NodeJS.
	# The rancher UI code running on MacOS (outside LimaVM) needs this for kubernetes download.
	configureNodeJSProxy ${USE_PROXY}

	local KCONTEXT=$(kubectl config current-context 2>/dev/null)
	echo "Using kubernetes context: ${KCONTEXT}"
	if [[ ${KCONTEXT} != "rancher-desktop" ]] ; then
		kubectl config use-context rancher-desktop 2>/dev/null
	fi

	# Stop rancher if it's already running, setup needs a cold start
	if "${RDCTL}" list-settings >/dev/null 2>&1 ; then
		echo "Shutting down rancher-desktop for reconfiguration..."
		"${RDCTL}" shutdown
	fi

	# Filter out flags from RD_CONFIG_ARGS which are not valid in this version
	RD_HELP_TEXT=$("${RDCTL}" set --help)
	for RD_ARG in ${RD_CONFIG_ARGS} ; do
		echo "${RD_HELP_TEXT}" | egrep -q " ${RD_ARG%%=*}(\s|\$)" && RD_VALID_ARGS="${RD_VALID_ARGS} ${RD_ARG}" || echo "Removing unsupported flag: ${RD_ARG}"
	done

	# Check MacOS for expired certificates which may affect startup
	# Ref: https://github.com/rancher-sandbox/rancher-desktop/issues/5165
	checkSystemCertificatesValidity

	# Check MacOS docker.sock file
	checkDockerSock || exit 1

	rm -f "${RD_OVERRIDE_YAML}" # force reconfiguration
	configureRancherDesktopProxy ${USE_PROXY}

	log "Configuring Rancher VM settings..."
	"${RDCTL}" version
	"${RDCTL}" start --path="${RD_APP}" ${RD_VALID_ARGS}
	[[ $? -eq 0 ]] || return $?

	# Wait for rancher to start, check status
	set -o pipefail
	while sleep 10 ; do
		VM_SETTINGS=$("${RDCTL}" list-settings 2>/dev/null)
		case ${VM_SETTINGS} in
			{*}) read VM_CPUS VM_MEM VM_KE VM_KV < <( echo "${VM_SETTINGS}" |
				"${JQ}" '.virtualMachine.numberCPUs, .virtualMachine.memoryInGB, .kubernetes.enabled, .kubernetes.version' |
				tr '\n"' ' ' ) ;;
		esac
		[[ ${VM_KE} == "false" ]] && VM_KV="disabled"
		case ${VM_CPUS} in
			[1-9]*) # successful list-settings, VM is coming up
				log "Rancher desktop is coming up"
				echo "CPUs:${VM_CPUS} Memory:${VM_MEM}Gb Kubernetes:${VM_KV}"
				break
				;;
		esac
	done
}

# Start rancher
# First prints the current internal proxy config
function startRancher {
	local USE_PROXY=$1

	if ${RDCTL} list-settings >/dev/null 2>&1 ; then
		echo "Rancher is already running, will shut down and restart in 10s... (CTRL-C to quit)"
		sleep 10
		${RDCTL} shutdown
	fi
	configureNodeJSProxy ${USE_PROXY}
	configureRancherDesktopProxy ${USE_PROXY}
	log "Starting rancher-desktop..."
	${RDCTL} start
}

# Restart rancher
function restartRancher {
	local USE_PROXY=$1
	if ${RDCTL} list-settings >/dev/null 2>&1 ; then
		log "Shutting down rancher-desktop..."
		${RDCTL} shutdown
	fi
	startRancher ${USE_PROXY}
}

# Print status info.
function showRancherStatus {
	local STATE='stopped'
	local SETTINGS
	local PROXY_STATUS

	${RDCTL} version
	${RDCTL} shell sh -c "uname -a; uptime" && STATE='running'
	echo -e "\nrancher-desktop is ${STATE}"
	if [[ ${STATE} == 'running' ]] ; then
		SETTINGS=( $(${RDCTL} list-settings | jq -r '
			[.virtualMachine, .experimental.virtualMachine, .kubernetes] | add | [
				.memoryInGB,
				.numberCPUs,
				.type,
				(if .useRosetta then "rosetta" else "" end),
				.mount.type,
				(if .enabled then .version else "disabled" end)
			] | join(" ")') )
		cat <<-EoM
			VM:             ${SETTINGS[1]} CPUs, ${SETTINGS[0]}GB
			Emulation:      ${SETTINGS[2]} ${SETTINGS[3]} ${SETTINGS[4]}
			Kubernetes:     ${SETTINGS[5]}
		EoM
		echo -e "\nDisk usage (use 'docker [builder|container|image|system] prune' to clean up):"
		docker system df
	fi

	echo -e "\nNetwork location: $(getNetworkLocation)"
	PROXY_STATUS=( $(getRancherDesktopProxyConfig) )
	echo -e "Proxy mode: ${PROXY_STATUS[*]}"
	if [[ ${STATE} == 'running' ]] ; then
		${RDCTL} shell env | grep -i 'proxy' | sort
	fi
	echo -e "\nLima VM config dir: ${RD_CONFIG}"
	echo -e "Download cache dir: ${RD_CACHE}"
	echo -e "Rancher logs dir:   ${RD_LOGS}"

	echo -e "\nHost OS:"
	uname -a
	sw_vers
}

# Search a list of possible paths for an app.
# echo the first found path and return 0
# if not found, return 1
function checkAppInstall {
	local APP
	for APP in "${@}" ; do
		if [[ -x "${APP}" ]] ; then
			echo "${APP}"
			return 0
		fi
	done
	return 1
}

# Return the network location [OFFICE|REMOTE]
function getNetworkLocation {
	local LOCATION="REMOTE"
	local NETWORK=$(system_profiler -json SPAirPortDataType | jq -r '.. | objects | .spairport_current_network_information | select(._name) | ._name')
	case ${NETWORK} in
		AlphaBeta-Corp) LOCATION="OFFICE" ;;
	esac
	echo ${LOCATION}
}

# Continue if user affirms
function continueYN {
    local prompt=${1:-"Are you sure"}
    local yn
    while [[ -z ${yn} ]] ; do
        echo -n "${prompt} (Yes/No) ? "
        read yn
        case ${yn} in
            yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) break ;;
            *) yn="" ;;
        esac
    done
	return 1
}

# Reset Kubernetes (deletes all resources)
function k8sReset {
	local K8S_ENABLED=$("${RDCTL}" list-settings 2>/dev/null | "${JQ}" '.kubernetes.enabled')
	if [[ "${K8S_ENABLED}" != "true" ]] ; then
		log "Kubernetes is not enabled."
		return
	fi
	if ! warnK8sReset ; then
		log "Kubernetes reset cancelled."
		return
	fi
	log "Deleting all kubernetes resources..."
	kubectl delete all --all --all-namespaces
	kubectl delete customresourcedefinitions,namespaces --all
	sleep 30
	log "Resetting kubernetes..."
	${RDCTL} set --kubernetes-enabled=false
	sleep 60
	log "Starting kubernetes..."
	${RDCTL} set --kubernetes-enabled=true
}

# Warn before kubernetes reset
function warnK8sReset {
	cat <<-EoM

		WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING

		This will reset kubernetes to the clean install state.
		This can be useful if you need to test with a clean cluster.
		* All local kubernetes resources will be deleted.
		* Local docker images will not be deleted.

		WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING

EoM
	continueYN
}

# Warn of complete configuration reset
function warnFactoryReset {
	cat <<-EoM

		WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING

		This will reset rancher-desktop to the unconfigured clean-install state.
		This can be useful if your environment has gotten into an unpredictable state.
		But beware:
		* All local docker images will be deleted.
		* All local kubernetes resources will be deleted.
		* Download cache ${RD_CACHE} will NOT be deleted.

		WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING

EoM
	continueYN
}

# Log message with timestamp
function log {
	local dt=$(TZ='UTC' date '+%Y-%m-%d %T %Z')
	echo "[${dt}] $*"
}

###############################################################################
# rancher launch script begin

# Kubernetes should be kept compatible with the version used on our Azure clusters
declare K8S_VERSION='1.31.10'
declare K8S_ENABLED='true'

# Proxy settings, if needed
declare APP_PROXY="http://application-proxy.blackrock.com:9443"
declare APP_NO_PROXY="localhost,.localdomain,.local,.svc,.internal"
APP_NO_PROXY="${APP_NO_PROXY},.bfm.com,.blkint.com,.blackrock.com,.azmk8s.io"
APP_NO_PROXY="${APP_NO_PROXY},::1,127.0.0.1,127.0.0.0/16,10.0.0.0/8,172.16.0.0/12,192.168.5.15,192.168.0.0/16,100.64.0.1,100.64.0.0/16"

declare RD_BIN=${HOME}/.rd/bin
declare RDCTL=${RD_BIN}/rdctl
declare RD_WIKI='https://webster.bfm.com/Wiki/display/IMAP/Rancher-Desktop+Installation+Notes'
export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"

# script options
declare PROG=${0##*/}
declare PROG_OPTS="$@"
declare O_ERR=0
declare O_CMD
declare O_K8S=1
declare O_PROXY=0
declare O_DEBUG=0

# Default to using proxy if on AlpaBeta-Corp network
# ZScaler rule-of-thumb is to use proxy when in-office and no proxy when remote.
declare NET_LOCATION=$(getNetworkLocation)
case ${NET_LOCATION} in
	OFFICE) O_PROXY=1 ;;
esac

while [[ $# -gt 0 ]]; do
	ARG="$1"
	shift
	case ${ARG} in
		--*) ARG=${ARG#-} ;; # --arg -> -arg
	esac
	case ${ARG} in
		-k|-k8s|-kubernetes) O_K8S="$1" ; shift ;;
		-p|-proxy|-o|-office) O_PROXY=1 ;;
		-n|-noproxy|-r|-remote|-vpn) O_PROXY=0 ;;
		-x|-X|-debug) O_DEBUG=1 ;;
		-?|-h|-help) O_ERR=1 ;;
		-*) echo "${PROG}: Unknown option: ${ARG}">&2 ; O_ERR=1 ;;
		start|run|go) O_CMD=start ;;
		stop|shut*) O_CMD=shutdown ;;
		settings) O_CMD=list-settings ;;
		setup|status|snapshot|clearlogs|logs|restart) O_CMD=${ARG} ;;
		shutdown|shell|version|list-settings|factory-reset|k8s-reset) O_CMD=${ARG} ;;
		help) O_ERR=2 ;;
		*) echo "${PROG}: Unknown command: ${ARG}">&2 ; O_ERR=1 ;;
	esac
done

case ${O_K8S} in
	disabled|false|off|no*|0) K8S_ENABLED=false ;;
	enabled|true|on|yes|1) K8S_ENABLED=true ;;
	[0-9].*) K8S_VERSION=${O_K8S}; K8S_ENABLED=true ;;
	*) echo "${PROG}: 'kubernetes' option must be a version, or boolean" >&2 ; O_ERR=1 ;;
esac

if [[ ${O_ERR} -gt 0 || -z "${O_CMD}" ]] ; then
	Usage ${PROG} ${O_ERR}
	exit 1
fi

[[ ${O_DEBUG} -gt 0 ]] && set -x

# Check for rd installation
declare RD_INSTALL="/Applications/Rancher Desktop.app"
declare RD_EXE="Contents/MacOS/Rancher Desktop"
declare RD_APP=$( checkAppInstall "${RD_INSTALL}/${RD_EXE}" "${HOME}${RD_INSTALL}/${RD_EXE}" )
if [[ ! -x "${RD_APP}" ]] ; then
	echo "Unable to locate '${RD_INSTALL##*/}' installation."
	echo "Please download from https://rancherdesktop.io/"
	echo "Install to ${RD_INSTALL%/*} or ${HOME}${RD_INSTALL%/*}"
	exit 2
fi
RD_APP="${RD_APP%/${RD_EXE}}"

if [[ ! -x ${RDCTL} ]] ; then
	log "WARNING: ${RDCTL} not found, assuming first-time setup."
	RDCTL="${RD_APP%/${RD_EXE}}/Contents/Resources/resources/darwin/bin/rdctl"

	if [[ ! -x "${RDCTL}" ]] ; then
		cat <<- EoM
			ERROR: ${RDCTL} not found, manual setup required.

			Please launch ${RD_APP#*/} via the desktop shortcut for first-time setup.
			Disable kubernetes, select Container Engine: dockerd(moby) and Configure PATH: Manual.
			Wait for it to finish starting, then run:
			$ ${PROG} ${PROG_OPTS:-setup}
		EoM
		exit 2
	fi

	if [[ ${O_CMD} != "setup" ]] ; then
		echo "ERROR: first-time launch, 'setup' required (was: '${O_CMD}')."
		exit 2
	fi
fi

# Rancher configuration
# These are Foresight recommended defaults, you may change them in the UI if necessary after initial "rancher setup"
declare RD_CONFIG_ARGS=" \
	--application.admin-access=false \
	--application.path-management-strategy=manual \
	--container-engine.name=moby \
	--experimental.virtual-machine.socket-vmnet=true \
	--experimental.virtual-machine.mount.type=virtiofs \
	--experimental.virtual-machine.type=vz \
	--experimental.virtual-machine.use-rosetta=true \
	--kubernetes.enabled=${K8S_ENABLED} \
	--kubernetes.version=${K8S_VERSION} \
	--kubernetes.options.traefik=false \
	--virtual-machine.memory-in-gb=16 \
	--virtual-machine.number-cpus=6 \
	--virtual-machine.type=vz \
	--virtual-machine.use-rosetta=true \
"

declare APP_SUPPORT="${HOME}/Library/Application Support"
declare RD_SUPPORT_DIR="${APP_SUPPORT}/rancher-desktop"
declare RD_CONFIG="${RD_SUPPORT_DIR}/lima/_config"
declare RD_CACHE="${HOME}/Library/Caches/rancher-desktop"
declare RD_OVERRIDE_YAML="${RD_CONFIG}/override.yaml"
declare RD_LOGS="${HOME}/Library/logs/rancher-desktop"

declare JQ=$( checkAppInstall "`which jq`" "/opt/homebrew/bin/jq" "/usr/local/bin/jq" "${CONDA_PREFIX}/bin/jq" )
if [[ ! -x "${JQ}" ]] ; then
	echo "Unable to locate 'jq' executable."
	echo "Please install, eg. using 'brew install jq'"
	exit 3
fi

# Ensure that RD can download kubernetes when running in-office
setupBLKCertificateChain

case ${O_CMD} in
	setup) setupRancherDesktop ${O_PROXY} ;;
	start) startRancher ${O_PROXY} ;;
	restart) restartRancher ${O_PROXY} ;;
	status) showRancherStatus ;;
	snapshot) configSnapshot "${RD_LOGS}" ;;
	clearlogs) clearLogs "${RD_LOGS}" ;;
	logs) showLogDir "${RD_LOGS}" ;;
	k8s-reset) k8sReset ;;
	factory-reset) warnFactoryReset && exec ${RDCTL} ${O_CMD} ;;
	shutdown|shell|version|list-settings) exec ${RDCTL} ${O_CMD} ;;
	*) echo "Unsupported command: ${O_CMD}"; exit 4 ;;
esac

exit $?
