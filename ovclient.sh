#!/bin/bash


die() { #{{{
	printf "ERROR: $1\n"; exit;
}
#}}}

check_status() { #{{{
	# As long as ./easyrsa returns 0 (success) we don't bother the non-verbose users
	should_be_empty=`echo $1 | sed 's/0//g'`
	[ "X$should_be_empty" == "X" ] || { cat $2; die "Failed for $client" ; }
	[ "X$VERBOSE" == "X1" ] && { cat $2; }
}
#}}}

revoke() { #{{{
	log=`mktemp`
	group_name=`groups nobody | cut -f2 -d: | cut -f2 -d' '`
	groups nobody | grep -q " $group_name" || { die "Failed at detecting group for user 'nobody'"; }
	cd /etc/openvpn/server/easy-rsa/
	./easyrsa --batch revoke "$1" &>> $log

	status+=$?;
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl &>> $log
	status+=$?;
	rm -f "/etc/openvpn/server/easy-rsa/pki/private/$1.key" 2>/dev/null
	rm -f "/etc/openvpn/server/easy-rsa/pki/issued/$1.crt" 2>/dev/null
	rm -f "/etc/openvpn/server/easy-rsa/pki/reqs/$1.req" 2>/dev/null
	rm -f /etc/openvpn/server/crl.pem
	cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
	chown nobody:"$group_name" /etc/openvpn/server/crl.pem
	id "$1" &>/dev/null && { userdel "$1"; }

	check_status $status $log 
	echo "OK! $1 revoked";
}
#}}}

add() { #{{{
	log=`mktemp`
	client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$1")
	client="vpn_$client"
	[ -e /etc/openvpn/server/easy-rsa/pki/issued/$client.crt ] && { die "$client exists"; }
	cd /etc/openvpn/server/easy-rsa/
	rm -f /etc/openvpn/server/easy-rsa/pki/private/$client.key 2>/dev/null

	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full $client nopass &>> $log
	status+=$?
	mkdir -p $OVUSERHOME/$client
	{
	cat /etc/openvpn/server/client-common.txt
	echo "<ca>"
	cat /etc/openvpn/server/easy-rsa/pki/ca.crt
	echo "</ca>"
	echo "<cert>"
	sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/$client.crt
	echo "</cert>"
	echo "<key>"
	cat /etc/openvpn/server/easy-rsa/pki/private/$client.key
	echo "</key>"
	echo "<tls-auth>"
	sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/ta.key
	echo "</tls-auth>"
	} > $OVUSERHOME/$client/${client}.ovpn
	chown -R $OVUSER $OVUSERHOME/$client

	check_status $status $log 
	echo "OK! $client created"
}
#}}}

list() { #{{{
	[ "X$1" == "Xalphabet" ] && {
		ls /etc/openvpn/server/easy-rsa/pki/issued/ | grep -v 'server.crt' | while read i; do
			echo $i | sed 's/\.crt$//'
		done
	} 
	[ "X$1" == "Xdate" ] && {
		ls -tlh /etc/openvpn/server/easy-rsa/pki/issued/ | grep -v 'server.crt' | while read i; do
			echo $i | sed 's/\.crt$//'
		done
	} 
}
#}}}

print_help() { #{{{
	cat << EOF
Options:
-l          list clients by date (ls /etc/openvpn/server/easy-rsa/pki/issued/)
-L          list clients by name
-a <name>   add client
-r <name>   revoke client
-v          be verbose
-h          this help

EOF
}
#}}}

# main {{{
	[ "X$SUDO_USER" != "X" ] && { OVUSER=$SUDO_USER; } || { OVUSER=$LOGNAME; }
	OVUSERHOME=$( eval echo ~$OVUSER );

	while getopts "lLa:r:gp:vh" opt; do
		case $opt in
			l) list date;;
			L) list alphabet;;
			a) ADDCLIENT=$OPTARG ;;
			r) revoke $OPTARG ;;
			v) VERBOSE=1 ;;
			h) print_help ;;
		esac
	done
	[ -n "$ADDCLIENT" ] && { 
		add $ADDCLIENT;
	}
#}}}
