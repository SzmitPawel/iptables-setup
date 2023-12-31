#!/bin/bash

### BEGIN INIT INFO
# Provides:          firewall.sh
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable service provided by daemon.
### END INIT INFO

# Name: Linux Firewall Iptables For Ubuntu
# Author: c3rb3rus
# Date Created: September 23, 2023
# Last Updated: September 26, 2023

####################################################################################################
# Script Purpose:
# The script aims to defaultly discard incoming and transit
# traffic, except for traffic originating from a whitelist
# of trusted sources.
# Outgoing traffic is typically allowed.
# There is awareness that the server may potentially be a
# source of attacks on other servers, suggesting the need
# to consider stricter rules for outgoing traffic if
# security concerns arise.
####################################################################################################

####################################################################################################
# Unification of terms
# To make it easier to understand, the terms of rules and
# comments are unified below
#
# ACCEPT : Authorization
# DROP   : Discard
# REJECT : Rejection
####################################################################################################

####################################################################################################
# Cheat sheet:
#
# -A, --append       Add one or more new rules to designated chain
# -D, --delete       Delete one or more rules from designated chain
# -P, --policy       Set the specified chain policy to the specified target
# -N, --new-chain    Create a new user-defined chain
# -X, --delete-chain Delete specified user-defined chain
# -F                 Table initialization
#
# -p, --protocol      protocol           Specify protocols (tcp, udp, icmp, all)
# -s, --source        IP address[/mask]  Source address. Describe IP address or host name
# -d, --destination   IP address[/mask]  Destination address. Describe IP address or host name
# -i, --in-interface  device             Specify the interface on which the packet comes in.
# -o, --out-interface device             Specify the interface on which the packet appears
# -j, --jump          target             Specify an action when a condition is met
# -t, --table         table              Specify table
# -m state --state    State              Specify condition of packet as condition
#                                        For state, NEW, ESTABLISHED, RELATED, INVALID can be specified
# !            Reverse condition (except for ~)
####################################################################################################

# Path
PATH=/sbin:/usr/sbin:/bin:/usr/bin

####################################################################################################
# IP Definitions:
# Define as necessary. It works even if it is not defined.
####################################################################################################

# Range allowed as internal network
# LOCAL_NET="xxx.xxx.xxx.xxx/xx"

# Scope permitting partial restriction as an internal network
# LIMITED_LOCAL_NET="xxx.xxx.xxx.xxx/xx"

# Define settings that represent all IPs
# ANY="0.0.0.0/0"

# Trusted hosts (array)
# ALLOW_HOSTS=(
#     "xxx.xxx.xxx.xxx"
#     "xxx.xxx.xxx.xxx"
#     "xxx.xxx.xxx.xxx"
# )

# Unconditionally blocked list (array)
# DENY_HOSTS=(
#     "xxx.xxx.xxx.xxx"
#     "xxx.xxx.xxx.xxx"
#     "xxx.xxx.xxx.xxx"
# )

####################################################################################################
# Port Definitions:
####################################################################################################
SSH=22 # Secure remote login and command execution.
FTP=20,21 # File transfer protocol for data and control.
DNS=53 # Domain name to IP address translation.
MDNS=5353 # Local network service discovery.
SMTP=25,465,587 # Email delivery and submission.
POP3=110,995 # Email retrieval.
IMAP=143,993 # Email retrieval with advanced features.
HTTP=80,443 # Web browsing and secure web browsing.
IDENT=113 # User identification for TCP connections.
NTP=123 # Network time synchronization.
MYSQL=3306 # MySQL database communication.
NET_BIOS_UDP=137,138 # NetBIOS name and datagram service over UDP.
NET_BIOS_TCP=139,445 # NetBIOS session and SMB hosting over TCP.
DHCP=67,68 # Dynamic host configuration for IP addresses.
CUPS=631 # Unix printing system over the network.
SNMP=161 # Network management and monitoring.
PROXY=3128 # Proxy server for network requests.
POSTGRE_SQL=5432 # PostgreSQL database communication.

####################################################################################################
# Functions:
####################################################################################################

# Initialize iptables, remove all rules
initialize() 
{
    iptables -F  # Table initialization
    iptables -X  # Delete chain
    iptables -Z  # Clear packet count · byte counter
    iptables -P INPUT   ACCEPT
    iptables -P OUTPUT  ACCEPT
    iptables -P FORWARD ACCEPT
}

# Process after rule application
finalize()
{
    /etc/init.d/linux-firewall-ubuntu.sh save &&  # Save settings
    /etc/init.d/linux-firewall-ubuntu.sh restart  # Try restarting with saved settings
    return 0
    return 1
}

# For development
if [ "$1" == "dev" ]
then
    iptables() { echo "iptables $@"; }
    finalize() { echo "finalize"; }
fi

####################################################################################################
# Initialization of iptables:
####################################################################################################
initialize

####################################################################################################
# Set Policies:
####################################################################################################
iptables -P INPUT   DROP  # Default to DROP for incoming traffic.
iptables -P OUTPUT  ACCEPT
iptables -P FORWARD DROP

####################################################################################################
# Trusted Hosts Allowed:
####################################################################################################

# Local host
# "lo" refers to the local loopback interface
iptables -A INPUT -i lo -j ACCEPT  # SELF -> SELF

# Local network
# If $LOCAL_NET is set, communication with other servers on the LAN is permitted
if [ "$LOCAL_NET" ]
then
    iptables -A INPUT -p tcp -s $LOCAL_NET -j ACCEPT  # LOCAL_NET -> SELF
fi

# Trusted hosts
# If $ALLOW_HOSTS is set, permission is granted to those hosts
if [ "${ALLOW_HOSTS}" ]
then
    for allow_host in "${ALLOW_HOSTS[@]}"
    do
        iptables -A INPUT -p tcp -s $allow_host -j ACCEPT  # allow_host -> SELF
    done
fi

####################################################################################################
# Discard Access from $DENY_HOSTS:
####################################################################################################
if [ "${DENY_HOSTS}" ]
then
    for deny_host in "${DENY_HOSTS[@]}"
    do
        iptables -A INPUT -s $deny_host -m limit --limit 1/s -j LOG --log-prefix "deny_host: "
        iptables -A INPUT -s $deny_host -j DROP
    done
fi

####################################################################################################
# Allow Packet Communication after Session Establishment:
####################################################################################################
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

####################################################################################################
# Other Rules and Security Measures:
####################################################################################################

####################################################################################################
# Attack countermeasure: Stealth Scan
####################################################################################################
iptables -N STEALTH_SCAN # Make a chain with the name "STEALTH_SCAN"
iptables -A STEALTH_SCAN -j LOG --log-prefix "stealth_scan_attack: "
iptables -A STEALTH_SCAN -j DROP

# Jump to "STEALTH_SCAN" chain for stealth scan-like packets
iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j STEALTH_SCAN

iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN         -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST         -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j STEALTH_SCAN

iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,FIN FIN     -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,PSH PSH     -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,URG URG     -j STEALTH_SCAN

####################################################################################################
# Attack countermeasure: Port scan by fragment packet, DOS attack
# Measures against fragmentation packets and DOS attacks
####################################################################################################
iptables -A INPUT -f -j LOG --log-prefix 'fragment_packet:'
iptables -A INPUT -f -j DROP
 
####################################################################################################
# Attack countermeasure: Ping of Death
# Create a chain named "PING_OF_DEATH"
# Discard if more than 1 ping per second lasts ten times
####################################################################################################
iptables -N PING_OF_DEATH
iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 10 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_PING_OF_DEATH \
         -j RETURN

# Discard ICMP exceeding limit
iptables -A PING_OF_DEATH -j LOG --log-prefix "ping_of_death_attack: "
iptables -A PING_OF_DEATH -j DROP

# ICMP jumps to "PING_OF_DEATH" chain
iptables -A INPUT -p icmp --icmp-type echo-request -j PING_OF_DEATH

####################################################################################################
# Attack measures: SYN Flood Attack
# In addition to this countermeasure, consider enabling Syn Cookie.
# Create a chain named "SYN_FLOOD"
####################################################################################################
iptables -N SYN_FLOOD
iptables -A SYN_FLOOD -p tcp --syn \
         -m hashlimit \
         --hashlimit 200/s \
         --hashlimit-burst 3 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_SYN_FLOOD \
         -j RETURN

# Commentary
# -m hashlimit                       Use hashlimit instead of limit to limit for each host
# --hashlimit 200/s                  Max 200 connections in a second
# --hashlimit-burst 3                Restriction is imposed if connection exceeding the above upper limit is three consecutive times
# --hashlimit-htable-expire 300000   Validity period of record in management table (unit: ms)
# --hashlimit-mode srcip             Manage requests by source address
# --hashlimit-name t_SYN_FLOOD       Hash table name saved in / proc / net / ipt_hashlimit
# -j RETURN                          If it is within the limit, it returns to the parent chain

# Discard SYN packet exceeding limit
iptables -A SYN_FLOOD -j LOG --log-prefix "syn_flood_attack: "
iptables -A SYN_FLOOD -j DROP

# SYN packet jumps to "SYN_FLOOD" chain
iptables -A INPUT -p tcp --syn -j SYN_FLOOD

####################################################################################################
# Attack measures: HTTP DoS/DDoS Attack
# Create a chain named "HTTP_DOS"
####################################################################################################
iptables -N HTTP_DOS
iptables -A HTTP_DOS -p tcp -m multiport --dports $HTTP \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 100 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_HTTP_DOS \
         -j RETURN

# Commentary
# -m hashlimit                       Use hashlimit instead of limit to limit for each host
# --hashlimit 1/s                    Maximum one connection per second
# --hashlimit-burst 100              It will be restricted if the above upper limit is exceeded 100 times in a row.
# --hashlimit-htable-expire 300000   Validity period of record in management table (unit: ms
# --hashlimit-mode srcip             Manage requests by source address
# --hashlimit-name t_HTTP_DOS        Hash table name saved in / proc / net / ipt_hashlimit
# -j RETURN                          If it is within the limit, it returns to the parent chain

# Discard connection exceeding limit
iptables -A HTTP_DOS -j LOG --log-prefix "http_dos_attack: "
iptables -A HTTP_DOS -j DROP

# Packets to HTTP jump to "HTTP_DOS" chain
iptables -A INPUT -p tcp -m multiport --dports $HTTP -j HTTP_DOS

####################################################################################################
# Attack measures: IDENT port probe
# Allow ident requests but respond with TCP resets to prevent misuse.
####################################################################################################
iptables -A INPUT -p tcp -m multiport --dports $IDENT -j REJECT --reject-with tcp-reset

####################################################################################################
# Attack measures: SSH Brute Force
# In case of server using password authentication, prepare for password brute force attack.
# Allow only five connection attempts per minute.
# To prevent SSH client from repeatedly reconnecting, use REJECT instead of DROP.
# Uncomment the following rules if SSH server uses password authentication.
####################################################################################################
# iptables -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --set
# iptables -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j LOG --log-prefix "ssh_brute_force: "
# iptables -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j REJECT --reject-with tcp-reset

####################################################################################################
# Attack measures: FTP Brute Force
# Prepare for password brute force attacks on FTP with password authentication.
# Allow only five connection attempts per minute.
# To prevent FTP client from repeatedly reconnecting, use REJECT instead of DROP.
# Uncomment the following rules when starting an FTP server.
####################################################################################################
# iptables -A INPUT -p tcp --syn -m multiport --dports $FTP -m recent --name ftp_attack --set
# iptables -A INPUT -p tcp --syn -m multiport --dports $FTP -m recent --name ftp_attack --rcheck --seconds 60 --hitcount 5 -j LOG --log-prefix "ftp_brute_force: "
# iptables -A INPUT -p tcp --syn -m multiport --dports $FTP -m recent --name ftp_attack --rcheck --seconds 60 --hitcount 5 -j REJECT --reject-with tcp-reset

####################################################################################################
# Discard packets addressed to all hosts (broadcast address, multicast address)
####################################################################################################
iptables -A INPUT -d 192.168.1.255   -j LOG --log-prefix "drop_broadcast: "
iptables -A INPUT -d 192.168.1.255   -j DROP
iptables -A INPUT -d 255.255.255.255 -j LOG --log-prefix "drop_broadcast: "
iptables -A INPUT -d 255.255.255.255 -j DROP
iptables -A INPUT -d 224.0.0.1       -j LOG --log-prefix "drop_broadcast: "
iptables -A INPUT -d 224.0.0.1       -j DROP

####################################################################################################
# Allow input from all hosts
# Replace ACCEPT with DROP to block port
####################################################################################################
# Rules definitions (uncomment to use):

# ICMP: Setting to respond to pings, for LAN users only
iptables -A INPUT -s 192.168.1.0/24 -p icmp -j ACCEPT

# HTTP, HTTPS (Apache) for all 
# iptables -A INPUT -p tcp -m multiport --dports $HTTP -j ACCEPT

# SSH: for all
iptables -A INPUT -p tcp -m multiport --dports $SSH -j ACCEPT

# DNS: for all
# iptables -A INPUT -p tcp -m multiport --sports $DNS -j ACCEPT
# iptables -A INPUT -p udp -m multiport --sports $DNS -j ACCEPT

# MDNS: for LAN users only
iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --sports $MDNS -j ACCEPT

# DHCP (dynamic host) for LAN users only
# iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --sports $DHCP -j ACCEPT

# NTP (time sync) for lan users only
# iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --dports $NTP -j ACCEPT

# PROXY (proxy server) for LAN users only
# iptables -A INPUT -s 192.168.1.0/24 -p tcp -m multiport --dports $PROXY -j ACCEPT

# SMTP: for all
# iptables -A INPUT -p tcp -m multiport --sports $SMTP -j ACCEPT

# POP3: for all
# iptables -A INPUT -p tcp -m multiport --sports $POP3 -j ACCEPT

# IMAP (Internet Message Access Protocol) for all
# iptables -A INPUT -p tcp -m multiport --sports $IMAP -j ACCEPT

# FTP (file transfer server) for all
# iptables -A INPUT -p tcp -m multiport --dports $FTP -j ACCEPT

# SAMBA (file server) for LAN users only
# iptables -A INPUT -s 192.168.1.0/24 -p tcp -m multiport --dports $NET_BIOS_TCP -j ACCEPT
# iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --dports $NET_BIOS_UDP -j ACCEPT

# CUPS (printing service) for LAN users only
# iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --dport $CUPS -j ACCEPT
# iptables -A INPUT -s 192.168.1.0/24 -p tcp -m multiport --dport $CUPS -j ACCEPT
# iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --dport $SNMP -j ACCEPT

# MYSQL (mysql server) for all
# iptables -A INPUT -p tcp -m multiport --dport $MYSQL -j ACCEPT

# POSTGRE SQL (PostgreSQL) for all
# iptables -A INPUT -p tcp -m multiport --dport $POSTGRE_SQL -j ACCEPT

####################################################################################################
# Allow input from local network (limited)
####################################################################################################

if [ "$LIMITED_LOCAL_NET" ]
then
	# SSH
	iptables -A INPUT -p tcp -s $LIMITED_LOCAL_NET -m multiport --dports $SSH -j ACCEPT # LIMITED_LOCAL_NET -> SELF
	
	# FTP
	iptables -A INPUT -p tcp -s $LIMITED_LOCAL_NET -m multiport --dports $FTP -j ACCEPT # LIMITED_LOCAL_NET -> SELF

	# MySQL
	iptables -A INPUT -p tcp -s $LIMITED_LOCAL_NET -m multiport --dports $MYSQL -j ACCEPT # LIMITED_LOCAL_NET -> SELF
fi

####################################################################################################
# Log and drop other packets
####################################################################################################
iptables -A INPUT  -j LOG --log-prefix "drop: "
iptables -A INPUT  -j DROP
