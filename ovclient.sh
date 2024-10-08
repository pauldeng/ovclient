#!/bin/bash

nextip() {
	IP=$1
	IFS="." read -r a b c d <<<"$IP"
	IP_HEX=$(printf "%02X%02X%02X%02X\n" "$a" "$b" "$c" "$d")
	if [[ $IP_HEX == *FE ]]; then
		# if 254, skip 255 and 0 and move to 1
		NEXT_IP_HEX=$(printf "%.8X" "$((0x$IP_HEX + 3))")
	elif [[ $IP_HEX == *FF ]]; then
		# if 255, skip 0 and move to 1
		NEXT_IP_HEX=$(printf "%.8X" "$((0x$IP_HEX + 2))")
	else
		NEXT_IP_HEX=$(printf "%.8X" "$((0x$IP_HEX + 1))")
	fi
	NEXT_IP=$(printf "%d.%d.%d.%d\n" $((0x${NEXT_IP_HEX:0:2})) $((0x${NEXT_IP_HEX:2:2})) $((0x${NEXT_IP_HEX:4:2})) $((0x${NEXT_IP_HEX:6:2})))
	echo "$NEXT_IP"
}

scanips() {
	tmpfile=$(mktemp /tmp/openvpn-client-ips.XXXXXX)

	if [ ! -d "/etc/openvpn/client/" ]; then
		echo >&2 "/etc/openvpn/client/ does not exist."
		exit 2
	fi

	files=$(
		shopt -s nullglob dotglob
		echo /etc/openvpn/client/*
	)
	if ((!${#files})); then
		echo >&2 "Need at least one static IP conf in /etc/openvpn/client/"
		exit 2
	fi

	# read all ip into a temp file
	for file in /etc/openvpn/client/*; do
		clientIpConf=$(<"$file")
		#echo "$clientIpConf"
		IFS=' ' read -r -a clientIpConfInput <<<"$clientIpConf"
		clientStaticIp=${clientIpConfInput[1]}
		echo "$clientStaticIp" >>"$tmpfile"
	done
	# sort ips in desc order in place
	sort -t . -nrk 1,1 -nrk 2,2 -nrk 3,3 -nrk 4,4 "$tmpfile" -o "$tmpfile"
}

die() {
	printf "ERROR:%s\n" "$1"
	exit
}

check_status() {
	# As long as ./easyrsa returns 0 (success) we don't bother the non-verbose users
	should_be_empty=$(echo "$1" | sed "s/0//g")
	[ "X$should_be_empty" == "X" ] || {
		cat "$2"
		die "Failed for $client"
	}
	[ "X$VERBOSE" == "X1" ] && { cat "$2"; }
}

revoke() {
	log=$(mktemp)
	group_name=$(groups nobody | cut -f2 -d: | cut -f2 -d" ")
	groups nobody | grep -q " $group_name" || { die "Failed at detecting group for user 'nobody'"; }
	cd /etc/openvpn/server/easy-rsa/ || exit
	./easyrsa --batch revoke "$1" &>>"$log"

	((status += $?))
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl &>>"$log"
	((status += $?))
	rm -f "/etc/openvpn/server/easy-rsa/pki/private/$1.key" 2>/dev/null
	rm -f "/etc/openvpn/server/easy-rsa/pki/issued/$1.crt" 2>/dev/null
	rm -f "/etc/openvpn/server/easy-rsa/pki/reqs/$1.req" 2>/dev/null
	rm -f /etc/openvpn/server/crl.pem
	cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
	chown nobody:"$group_name" /etc/openvpn/server/crl.pem
	id "$1" &>/dev/null && { userdel "$1"; }

	check_status "$status" "$log"
}

add() {
	SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
	ABSOLUTE_OVPN_OUTPUT_DIR="$SCRIPT_DIR"/ovpns/
	log=$(mktemp)

	if [ $# -ge 2 ]; then
		#echo "2 arguments supplied"
		# the ip has to within 10.8.0.1 - 10.8.255.255
		# auto: try to allocate the largest ip address
		# ip address: try to allocate that number
		if [[ $2 =~ 10+\.8+\.[0-9]+\.[0-9]+$ ]]; then
			ip="$2"
			# echo "Allocating IP address $ip"
			# scan all ips to find the current max
			scanips
			if grep -Fxq "$ip" "$tmpfile"; then
				# code if found
				echo "ERROR:This $ip is already configured"
				exit
			else
				# code if not found
				# echo "This $ip is available"
				nextIp=$ip
			fi
		elif [ "$2" == "auto" ]; then
			# echo "Allocate IP address automatically"
			# scan all ips to find the current max
			scanips
			currentIp=$(head -n 1 "$tmpfile")
			#echo "$currentIp"
			nextIp=$(nextip "$currentIp")
			#echo "$nextIp"
		else
			echo "ERROR:Invalid static IP address"
			exit
		fi

		if [ -n "$3" ]; then
			# Absolute output path for ovpn file
			# Example is /home/ubuntu/openvpn_keys/
			ABSOLUTE_OVPN_OUTPUT_DIR="$3"
		fi
	fi

	client=$(sed "s/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g" <<<"$1")
	[ -e /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt ] && { die "$client exists"; }
	cd /etc/openvpn/server/easy-rsa/ || exit

	# If more recent easy-rsa is used, you should use
	# EASYRSA_BATCH=1 EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass &>> "$log"
	# This works for easy-rsa 3.1.0
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass &>>"$log"
	((status += $?))
	mkdir -p "$ABSOLUTE_OVPN_OUTPUT_DIR"
	# Generates the custom client.ovpn
	{
		# if static ip is allocated, add it to comment of client ovpn file
		if [[ -n "$nextIp" ]]; then
			echo "# static ip address:$nextIp"
		fi
		cat /etc/openvpn/server/client-common.txt
		echo "<ca>"
		cat /etc/openvpn/server/easy-rsa/pki/ca.crt
		echo "</ca>"
		echo "<cert>"
		sed -ne "/BEGIN CERTIFICATE/,$ p" /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt
		echo "</cert>"
		echo "<key>"
		cat /etc/openvpn/server/easy-rsa/pki/private/"$client".key
		echo "</key>"
		echo "<tls-auth>"
		sed -ne "/BEGIN OpenVPN Static key/,$ p" /etc/openvpn/server/ta.key
		echo "</tls-auth>"
	} >"$ABSOLUTE_OVPN_OUTPUT_DIR""${client}".ovpn
	# echo "$ABSOLUTE_OVPN_OUTPUT_DIR""${client}".ovpn
	chown -R "$OVUSER" "$ABSOLUTE_OVPN_OUTPUT_DIR"

	check_status "$status" "$log"

	# if static ip is allocated, add configuration to /etc/client/
	if [[ -n "$nextIp" ]]; then
		#echo "lwa"
		# { printf "ifconfig-push %s 255.255.0.0" "$nextIp" } > /etc/openvpn/client/"${client}"
		echo "ifconfig-push $nextIp 255.255.0.0" >/etc/openvpn/client/"${client}"

		rm -r "$tmpfile"

		echo "OK:$client,$nextIp created"
	else
		echo "OK:$client created"
	fi
}

list() {
	[ "X$1" == "Xalphabet" ] && {
		ls /etc/openvpn/server/easy-rsa/pki/issued/ | grep -v "server.crt" | while read -r i; do
			echo "$i" | sed "s/\.crt$//"
		done
	}
	[ "X$1" == "Xdate" ] && {
		ls -tlh /etc/openvpn/server/easy-rsa/pki/issued/ | grep -v "server.crt" | while read -r i; do
			echo "$i" | sed "s/\.crt$//"
		done
	}
}

print_help() {
	cat <<EOF
Options:
-l          list clients by date (ls /etc/openvpn/server/easy-rsa/pki/issued/)
-L          list clients by name
-a <name>   add client  -s add static ip address ["auto", "10.8.0.46"] -O absloute output ovpn path
-r <name>   revoke client
-v          be verbose
-h          this help

EOF
}

#Remove the lock directory
cleanup() {
	if ! rmdir -- "$LOCKDIR"; then
		echo >&2 "ERROR:Failed to remove lock directory $LOCKDIR"
		exit 1
	fi
}

# main {{{
[ "X$SUDO_USER" != "X" ] && { OVUSER=$SUDO_USER; } || { OVUSER=$LOGNAME; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LOCKDIR="${SCRIPT_DIR}/.ovclient-lock"

# try 10 times
MAX=10

for i in $(seq 1 "$MAX"); do
	if mkdir -- "$LOCKDIR"; then
		#Ensure that if we "grabbed a lock", we release it
		#Works for SIGTERM and SIGINT(Ctrl-C) as well in some shells
		#including bash.
		trap "cleanup" EXIT

		while getopts "lLa:s:O:r:vh" opt; do
			case "$opt" in
			l) list date ;;
			L) list alphabet ;;
			a) ADDCLIENT=$OPTARG ;;
			s) staticIp=$OPTARG ;;
			O) absOutputPath=$OPTARG ;;
			r) revoke "$OPTARG" ;;
			v) VERBOSE=1 ;;
			h) print_help ;;
			*) echo -n "ERROR:unknown parameter" ;;
			esac
		done

		if [ -n "$ADDCLIENT" ] && [ -z "$staticIp" ] && [ -z "$absOutputPath" ]; then
			add "$ADDCLIENT"
		elif [ -n "$ADDCLIENT" ] && [ -n "$staticIp" ] && [ -z "$absOutputPath" ]; then
			add "$ADDCLIENT" "$staticIp"
		elif [ -n "$ADDCLIENT" ] && [ -n "$staticIp" ] && [ -n "$absOutputPath" ]; then
			add "$ADDCLIENT" "$staticIp" "$absOutputPath"
		fi

		break

	else
		if [ "$i" -ge $MAX ]; then
			echo >&2 "Error:Failed to create lock directory $LOCKDIR"
			exit 2
		fi

		#echo >&2 "Warning:$i Trying to create lock directory $LOCKDIR"
		# wait 500ms and retry
		sleep 0.5
	fi
done
#}}}
