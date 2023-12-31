*filter

# Name: Linux Firewall Iptables For Raspberry Pi
# Author: C3rb3rus
# Date Created: September 24, 2023
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

####################################################################################################
# Port Definitions:
####################################################################################################
# SSH=22 - Secure remote login and command execution.
# FTP=20,21 - File transfer protocol for data and control.
# DNS=53 - Domain name to IP address translation.
# MDNS=5353 - Local network service discovery.
# SMTP=25,465,587 - Email delivery and submission.
# POP3=110,995 - Email retrieval.
# IMAP=143,993 - Email retrieval with advanced features.
# HTTP=80,443 - Web browsing and secure web browsing.
# IDENT=113 - User identification for TCP connections.
# NTP=123 - Network time synchronization.
# MYSQL=3306 - MySQL database communication.
# NET_BIOS_UDP=137,138 - NetBIOS name and datagram service over UDP.
# NET_BIOS_TCP=139,445 - NetBIOS session and SMB hosting over TCP.
# DHCP=67,68 - Dynamic host configuration for IP addresses.
# CUPS=631 - Unix printing system over the network.
# SNMP=161 - Network management and monitoring.
# PROXY=3128 - Proxy server for network requests.
# POSTGRE_SQL=5432 - PostgreSQL database communication.

####################################################################################################
# Set Policies: Default to DROP for incoming traffic.
####################################################################################################
-P INPUT   DROP
-P OUTPUT  ACCEPT
-P FORWARD DROP

####################################################################################################
# Allow Packet Communication after Session Establishment:
####################################################################################################
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

####################################################################################################
# Other Rules and Security Measures:
####################################################################################################

####################################################################################################
# Attack countermeasure: Stealth Scan
# Create a chain named "STEALTH_SCAN"
####################################################################################################
-N STEALTH_SCAN
-A STEALTH_SCAN -j LOG --log-prefix "stealth_scan_attack: "
-A STEALTH_SCAN -j DROP

# Jump to "STEALTH_SCAN" chain for stealth scan-like packets
-A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j STEALTH_SCAN
-A INPUT -p tcp --tcp-flags ALL NONE -j STEALTH_SCAN

-A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN         -j STEALTH_SCAN
-A INPUT -p tcp --tcp-flags SYN,RST SYN,RST         -j STEALTH_SCAN
-A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j STEALTH_SCAN

-A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j STEALTH_SCAN
-A INPUT -p tcp --tcp-flags ACK,FIN FIN     -j STEALTH_SCAN
-A INPUT -p tcp --tcp-flags ACK,PSH PSH     -j STEALTH_SCAN
-A INPUT -p tcp --tcp-flags ACK,URG URG     -j STEALTH_SCAN

####################################################################################################
# Attack countermeasure: Port scan by fragment packet, DOS attack
# Measures against fragmentation packets and DOS attacks
####################################################################################################
-A INPUT -f -j LOG --log-prefix "fragment_packet: "
-A INPUT -f -j DROP

####################################################################################################
# Attack countermeasure: Ping of Death
# Create a chain named "PING_OF_DEATH"
# Discard if more than 1 ping per second lasts ten times
####################################################################################################
-N PING_OF_DEATH
-A PING_OF_DEATH -p icmp --icmp-type echo-request -m hashlimit --hashlimit 1/s --hashlimit-burst 10 --hashlimit-htable-expire 300000 --hashlimit-mode srcip --hashlimit-name t_PING_OF_DEATH -j RETURN

# Discard ICMP exceeding limit
-A PING_OF_DEATH -j LOG --log-prefix "ping_of_death_attack: "
-A PING_OF_DEATH -j DROP

# ICMP packets jump to "PING_OF_DEATH" chain
-A INPUT -p icmp --icmp-type echo-request -j PING_OF_DEATH

####################################################################################################
# Attack measures: SYN Flood Attack
# In addition to this countermeasure, consider enabling Syn Cookie.
# Create a chain named "SYN_FLOOD"
####################################################################################################
-N SYN_FLOOD
-A SYN_FLOOD -p tcp --syn -m hashlimit --hashlimit 200/s --hashlimit-burst 3 --hashlimit-htable-expire 300000 --hashlimit-mode srcip --hashlimit-name t_SYN_FLOOD -j RETURN

# Commentary
# -m hashlimit                       Use hashlimit instead of limit to limit for each host
# --hashlimit 200/s                  Max 200 connections in a second
# --hashlimit-burst 3                Restriction is imposed if connection exceeding the above upper limit is three consecutive times
# --hashlimit-htable-expire 300000   Validity period of record in management table (unit: ms
# --hashlimit-mode srcip             Manage requests by source address
# --hashlimit-name t_SYN_FLOOD       Hash table name saved in / proc / net / ipt_hashlimit
# -j RETURN                          If it is within the limit, it returns to the parent chain

# Discard SYN packet exceeding limit
-A SYN_FLOOD -j LOG --log-prefix "syn_flood_attack: "
-A SYN_FLOOD -j DROP

# SYN packet jumps to "SYN_FLOOD" chain
-A INPUT -p tcp --syn -j SYN_FLOOD

####################################################################################################
# Attack measures: HTTP DoS/DDoS Attack
# Create a chain named "HTTP_DOS"
####################################################################################################
-N HTTP_DOS
-A HTTP_DOS -p tcp -m multiport --dports 80,443 -m hashlimit --hashlimit 1/s --hashlimit-burst 100 --hashlimit-htable-expire 300000 --hashlimit-mode srcip --hashlimit-name t_HTTP_DOS -j RETURN

# Commentary
# -m hashlimit                       Use hashlimit instead of limit to limit for each host
# --hashlimit 1/s                    Maximum one connection per second
# --hashlimit-burst 100              It will be restricted if the above upper limit is exceeded 100 times in a row.
# --hashlimit-htable-expire 300000   Validity period of record in management table (unit: ms)
# --hashlimit-mode srcip             Manage requests by source address
# --hashlimit-name t_HTTP_DOS        Hash table name saved in / proc / net / ipt_hashlimit
# -j RETURN                          If it is within the limit, it returns to the parent chain

# Discard connection exceeding limit
-A HTTP_DOS -j LOG --log-prefix "http_dos_attack: "
-A HTTP_DOS -j DROP

# Packets to HTTP jump to "HTTP_DOS" chain
-A INPUT -p tcp -m multiport --dports 80,443 -j HTTP_DOS

####################################################################################################
# Attack measures: IDENT port probe
# Allow ident requests but respond with TCP resets to prevent misuse.
####################################################################################################
-A INPUT -p tcp -m tcp --dport 113 -j REJECT --reject-with tcp-reset

####################################################################################################
# Attack measures: SSH Brute Force
# In case of server using password authentication, prepare for password brute force attack.
# Allow only five connection attempts per minute.
# To prevent SSH client from repeatedly reconnecting, use REJECT instead of DROP.
# Uncomment the following rules if SSH server uses password authentication.
####################################################################################################
# -A INPUT -p tcp --syn --dport 22 -m recent --name ssh_attack --set
# -A INPUT -p tcp --syn --dport 22 -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j LOG --log-prefix "ssh_brute_force: "
# -A INPUT -p tcp --syn --dport 22 -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j REJECT --reject-with tcp-reset

####################################################################################################
# Attack measures: FTP Brute Force
# Prepare for password brute force attacks on FTP with password authentication.
# Allow only five connection attempts per minute.
# To prevent FTP client from repeatedly reconnecting, use REJECT instead of DROP.
# Uncomment the following rules when starting an FTP server.
####################################################################################################
# -A INPUT -p tcp --syn -m multiport --dports 20,21 -m recent --name ftp_attack --set
# -A INPUT -p tcp --syn -m multiport --dports 20,21 -m recent --name ftp_attack --rcheck --seconds 60 --hitcount 5 -j LOG --log-prefix "ftp_brute_force: "
# -A INPUT -p tcp --syn -m multiport --dports 20,21 -m recent --name ftp_attack --rcheck --seconds 60 --hitcount 5 -j REJECT --reject-with tcp-reset

####################################################################################################
# Discard packets addressed to all hosts (broadcast address, multicast address)
####################################################################################################
-A INPUT -d 192.168.1.255   -j LOG --log-prefix "drop_broadcast: "
-A INPUT -d 192.168.1.255   -j DROP
-A INPUT -d 255.255.255.255 -j LOG --log-prefix "drop_broadcast: "
-A INPUT -d 255.255.255.255 -j DROP
-A INPUT -d 224.0.0.1       -j LOG --log-prefix "drop_broadcast: "
-A INPUT -d 224.0.0.1       -j DROP

####################################################################################################
# Allow input from all hosts
# Replace ACCEPT with DROP to block port
####################################################################################################
# Rules definitions (uncomment to use):

# ICMP: Setting to respond to pings, for LAN users only
-A INPUT -s 192.168.1.0/24 -p icmp -j ACCEPT

# HTTP, HTTPS (Apache) for all
# -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

# SSH: for all
-A INPUT -p tcp --dport 22 -j ACCEPT

# DNS: for all
# -A INPUT -p tcp --sport 53 -j ACCEPT
# -A INPUT -p udp --sport 53 -j ACCEPT

# MDNS: for LAN users only
-A INPUT -s 192.168.1.0/24 -p udp --sport 5353 -j ACCEPT

# DHCP (dynamic host) for LAN users only 
# -A INPUT -s 192.168.1.0/24 -p udp -m multiport --sports 67,68 -j ACCEPT

# NTP (time sync) for LAN users only
# -A INPUT -s 192.168.1.0/24 -p udp --dport 123 -j ACCEPT

# PROXY (proxy server) for LAN users only
# -A INPUT -s 192.168.1.0/24 -p tcp --dport 3128 -j ACCEPT

# SMTP: for all
# -A INPUT -p tcp -m multiport --sports 25,465,587 -j ACCEPT

# POP3: for all
# -A INPUT -p tcp -m multiport --sports 110,995 -j ACCEPT

# IMAP (Internet Message Access Protocol) for all
# -A INPUT -p tcp -m multiport --sports 143,993 -j ACCEPT

# FTP (file transfer server) for all
# -A INPUT -p tcp -m multiport --dports 20,21 -j ACCEPT

# SAMBA (file server) for LAN users only
# -A INPUT -s 192.168.1.0/24 -p tcp -m multiport --dports 139,445 -j ACCEPT
# -A INPUT -s 192.168.1.0/24 -p udp -m multiport --dports 137,138,139,445 -j ACCEPT

# CUPS (printing service) for LAN users only
# -A INPUT -s 192.168.1.0/24 -p udp --dport 631 -j ACCEPT
# -A INPUT -s 192.168.1.0/24 -p tcp --dport 631 -j ACCEPT
# -A INPUT -s 192.168.1.0/24 -p udp --dport 161 -j ACCEPT

# MYSQL (mysql server) for all
# -A INPUT -p tcp --dport 3306 -j ACCEPT

# POSTGRE SQL (PostgreSQL) for all
# -A INPUT -p tcp --dport 5432 -j ACCEPT

####################################################################################################
# Log and drop other packets
####################################################################################################
-A INPUT  -j LOG --log-prefix "drop: "
-A INPUT  -j DROP

COMMIT
