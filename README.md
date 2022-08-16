# Nyr's OpenVPN Client

This is the command line client for [Nyr's OpenVPN Installer](https://github.com/Nyr/openvpn-install).

## Disclaimer

I am sure you know what you are doing, right? Please test it before any serious work , mate.

Note: this script is only tested in Ubuntu.

## Description

This ovclient try to address some use cases of the installer script to improve usability:

- non-interactive: accepts parameters for add/revoke
- safer: you cannot accidentally uninstall OpenVPN server

This script is forked from [Karol Kreński](https://github.com/mimooh/ovclient) with following customizations:

- Removed optional google authenticator support
- Added optional static ip address allocation

## Getting Started

### Installing

1. Install [Nyr's OpenVPN Installer](https://github.com/Nyr/openvpn-install)
2. Download this script and use

### Add user

```sh
# add user7 with dynamic ip
sudo ./ovclient.sh -a user7

# to use static ip allocation, the /etc/openvpn/server/server.conf should contain "client-config-dir /etc/openvpn/client".

# add user7 with next available static ip
sudo ./ovclient.sh -a user7 -s auto
# ovclient scans the /etc/openvpn/client/* to find the next available ip
# for example, the next ip is 10.8.0.46 for 10.8.0.45
# ip end with 255 or 0 are skipped, for example 10.8.0.255, 10.8.1.0, ... are skipped
# ovclient creates user7 file in /etc/openvpn/client/ with the allocated ip address
# ovclient creates user7.ovpn and the allocated ip address is embedded in the comment

# add user7 with specified static ip
sudo ./ovclient.sh -a user7 -s 10.8.0.46
# ovclient scans the /etc/openvpn/client/* to find if the ip specified available
# ovclient creates user7 file in /etc/openvpn/client/ with the allocated ip address
# ovclient creates user7.ovpn and the allocated ip address is embedded in the comment

```

### Revoke user

```sh
# revoke user7
sudo ./ovclient.sh -r user7

# revoke user will not automatically remove the static ip config file in /etc/openvpn/client.
```

### List users

```sh
# list users by date
sudo ./ovclient.sh -l

# list users by date
sudo ./ovclient.sh -L
```

## Acknowledgments

* [Karol Kreński](https://github.com/mimooh)