{% if grains['os_family'] == 'RedHat' and grains['osrelease'].startswith('6') %}

## Copy CIS scripts:
# Moved to cis-scripts.sls so it can be run separately
# Much of cis.sls will not run with test=True without
# the existence of these scripts.
#cis_copy_scripts:
#  file:
#    - recurse
#    - name: /opt/cis/scripts  
#    - source: salt://cis/scripts
#    - file_mode: 755
#    - dir_mode: 700
#    - template: jinja
#    - clean: True
include:
  - cis-scripts

## Package Management:
cis_install_pkgs:
  pkg.installed:
    - pkgs:
      - postfix
      - vlock
      - aide
      - rsyslog
      - tcp_wrappers
      - cronie-anacron

## Default CIS packages to remove:
{% set default_cis_pkgs_to_remove = ['xinetd', 'telnet', 'telnet-server', 'krb5-workstation',
'rsh-server', 'rsh', 'tftp-server', 'sendmail', 'dhcp', 'gnome-user-share','isdn4k-utils',
'irda-utils', 'talk', 'ipsec-tools', 'pam_ccreds', 'openswan', 'sysklogd', 'openldap-servers',
'openldap-clients', 'setroubleshoot', 'bind', 'vsftpd', 'httpd', 'dovecot', 'samba',
'squid', 'net-snmp' ] %}

cis_removed_pkgs:
  pkg.purged:
    - pkgs:
      ## Check for packages in pillar otherwise use default CIS packages:
      {% for pkg in pillar.get('cis_pkgs_to_remove', default_cis_pkgs_to_remove) %}
      - {{pkg}}
      {% endfor %}

## 1.1.1 Create Separate Partition for /tmp (Scored)
## 1.1.5 Create Separate Partition for /var (Scored)
## 1.1.7 Create Separate Partition for /var/log (Scored)
## 1.1.8 Create Separate Partition for /var/log/audit (Scored)
## 1.1.9 Create Separate Partition for /home (Scored)
## Should be done while creating the system

## 1.1.2 Set nodev option for /tmp Partition (Scored)
## 1.1.3 Set nosuid option for /tmp Partition (Scored)
## 1.1.4 Set noexec option for /tmp Partition (Scored)
## 1.1.10 Add nodev Option to /home (Scored)
## 1.1.14 Add nodev Option to /dev/shm Partition (Scored)
## 1.1.15 Add nosuid Option to /dev/shm Partition (Scored)
## 1.1.16 Add noexec Option to /dev/shm Partition (Scored)
{% for device, fsoptions in [ ('/tmp', 'nodev,noexec,nosuid' ), ('/var', 'nodev'),
('/var/log', 'nodev,noexec,nosuid'), ('/var/log/audit', 'nodev,noexec,nosuid'),
('/home', 'nodev'), ('/dev/shm', 'defaults,nodev,noexec,nosuid') ]  %}

# First check if the mount point exist in the fstab file for {{device}}:
# note: the are intentional space characters before and after the device name 
# to prevent grep x`errors.
{% set partition_exist = salt['cmd.run']("grep -c ' " + device + " ' /etc/fstab") %}
{% if partition_exist == '1' %}
#Mount_point_exists= {{partition_exist}}
# Get the current mount options
{% set current_opts = salt['cmd.run']("grep ' " + device + " ' /etc/fstab  | awk '{print $4}'")  %}
#Current_dev = {{device}}
#Current_opts= {{current_opts}}
#Salt_fsoptions= {{fsoptions}}

{% if fsoptions  != current_opts %}

fstab_{{ device }}:
  file:
    - replace
    - name: /etc/fstab
    - pattern: '(\s\{{device}}\s.*)({{current_opts}})'
    - repl: '\1{{fsoptions}}'
    - count: 1  

{% endif %}
{% endif %}
{% endfor %}

## 1.1.6 Bind Mount the /var/tmp directory to /tmp (Scored)
# Add it to fstab:
{% if 'bind' not in salt['cmd.run']('grep -e "^/tmp" /etc/fstab | grep /var/tmp') %}
append_var_tmp:
  file:
    - append
    - name: /etc/fstab
    - text: '/tmp /var/tmp none bind 0 0'
{% endif %}

# Mount it if not currently mounted:
{% set drive_mounted = salt['cmd.run']('mount | grep -e "^/tmp" | grep /var/tmp') %}
{% if drive_mounted != '/tmp on /var/tmp type none (rw,bind)' %}
mount_var_tmp:
  cmd.run:
    - name: 'mount --bind /tmp /var/tmp'
{% endif%}

## 1.2.2 Verify Red Hat GPG Key is Installed
gpg_check:
  cmd.run:
    - name: /opt/cis/scripts/1.2.2.gpg-keys.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/1.2.2.gpg-keys.sh
    - watch:
      - file.recourse: /opt/cis/scripts     
        
## 1.2.3 Verify that gpgcheck is Globally Activated
gpgcheck_sed:
  file:
    - sed
    - name: /etc/yum.conf
    - before: gpgcheck=0
    - after: gpgcheck=1
    
## 1.2.4 Disable the rhnsd Daemon
rhnsd:
  service:
    - {{ 'running' if pillar.get('enable_rhnsd', false)  else 'disabled' }}
    - name: rhnsd
    - enable: {{ 'True' if pillar.get('enable_rhnsd', false)  else 'False' }}
    - sig: rhnsd
    
## 1.2.5 Obtain Software Package Updates with yum (Not Implemented)
## 1.2.6 Verify Package Integrity Using RPM 
## Will not implement; there are some isues with the proposed script
## Issues with prelink and rpm verify 
## https://bugzilla.redhat.com/show_bug.cgi?id=204448
    
## 1.3.1 Install AIDE
## Up in package management

## 1.3.2 Implement Periodic Execution of File Integrity
/usr/sbin/aide --check:
  cron.present:
    - user: root
    - minute: 0
    - hour: 5
    
## 1.4.1 Enable SELinux in /etc/grub.conf
grub_selinux:
  file:
    - sed
    - name: /etc/grub.conf
    - before: selinux=0
    - after: selinux=1

## 1.4.2 Set the SELinux State
## 1.4.3 Set the SELinux Policy
/etc/selinux/config:
  file:
    - managed
    - source: salt://cis/files/etc.selinux.config
    - mode: 644
    - template: jinja
    
# Install salt pkg dependency for selinux state:
policycoreutils:
  pkg.installed

policycoreutils-python:
  pkg.installed 
  
# Make sure that SELinux is actually running:   
cis_selinux:
    selinux:
      - mode
      - name: {{ salt['pillar.get']('selinux_state', 'enforcing') }}
      - require:
        - pkg: policycoreutils
        - pkg: policycoreutils-python

## 1.4.4 Remove SETroubleshoot
## 1.4.5 Remove MCS Translation Service
## Up in package management

## 1.4.6 Check for Unconfined Daemons (on audit)
unconfied_daemon_check:
  cmd.run:
    - name: /opt/cis/scripts/1.4.6.check.for.unconfined.daemons.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/1.4.6.check.for.unconfined.daemons.sh
    - watch:
      - file.recourse: /opt/cis/scripts  

## 1.5.1 Set User/Group Owner on /etc/grub.conf
## 1.5.2 Set Permissions on /etc/grub.conf
/etc/grub.conf:
  file:
    - managed
    - mode: 600
    - user: root
    - group: root 
    
## 1.5.3 Set Boot Loader Password
# First check for md5 password in pillar
{% if 'grub_change_password' in pillar and pillar['grub_change_password'] and
'grub_md5_password' in pillar and pillar['grub_md5_password'].startswith('$1') %}

  {% set grub_config = '/boot/grub/grub.conf' %}
  {% set grub_test = salt['cmd.run']("grep ' password --md5' " + grub_config )  %}
  ## this is grub_test = {{grub_test}}

  # Check for desired password line:
  {% if grub_test != " password --md5 " + pillar['grub_md5_password'] %}
    {% set grub_pass_count = salt['cmd.run']("grep -c ' password --md5' " + grub_config ) %}
    
    # Check if password doesn't exist in grub.conf
    {% if grub_pass_count == '0' %}
    {% set grub_pass_line = " password --md5 " + pillar['grub_md5_password'] %}
grub_manual_sed:
  cmd.run:
    ## Note: we need the \\n to escape the newline in the template
    ## only one backslash needed in a real command line.
    - name: "sed -i '0,/^title/s||{{grub_pass_line}}\\n&|' {{grub_config}}"

    {% else %}
{{grub_config}}:
  file.sed:
  - before: 'password.*'
  - after: "password --md5 {{pillar['grub_md5_password']}}"
  - limit: "^ password"
  - backup: ''
     
    {% endif %}
  
  # endif of grub_test
  {% endif %}

# endif of pillar['grub_md5_password']
{% endif %}

## 1.5.4 Require Authentication for Single-User Mode
## 1.5.5 Disable Interactive Boot
sysconfig_init_single:
  file:
    - sed
    - name: /etc/sysconfig/init
    - before: SINGLE=/sbin/sushell
    - after: SINGLE=/sbin/sulogin 
    - limit: '^SINGLE'

sysconfig_init_prompt:
  file:
    - sed
    - name: /etc/sysconfig/init
    - before: PROMPT=yes
    - after: PROMPT=no
    - limit: '^PROMPT'

## 1.6.1 Restrict Core Dumps 
/etc/security/limits.conf:
  file:
    - managed
    - source: salt://cis/files/etc.security.limits.conf
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    
fs.suid_dumpable:
  sysctl:
    - present
    - value: 0


## 1.6.2 Configure ExecShield 
kernel.exec-shield:
  sysctl:
    - present
    - value: 1
    
## 1.6.3 Enable Randomized Virtual Memory Region Placement
kernel.randomize_va_space:
  sysctl:
    - present
    - value: 2
    
## 1.7 Use the Latest OS Release (Not Scored)
## Not Implemented

#### 2.1 Remove Legacy Services ####
## 2.1.1 Remove telnet-server
## 2.1.2 Remove telnet Clients
## 2.1.3 Remove rsh-server
## 2.1.5 Remove NIS Client 
## 2.1.6 Remove NIS Server
## 2.1.8 Remove tftp-server
## 2.1.9 Remove talk 
## 2.1.11 Remove xinetd 
## Up in package management 


## 2.1.12 Disable chargen-dgram 
chargen-dgram:
  service:
    - {{ 'running' if pillar.get('enable_chargen-dgram', false)  else 'disabled' }}
    - name: chargen-dgram
    - enable: {{ 'True' if pillar.get('enable_chargen-dgram', false)  else 'False' }}
    - sig: chargen-dgram

## 2.1.13 Disable chargen-stream endif
chargen-stream:
  service:
    - {{ 'running' if pillar.get('enable_chargen-stream', false)  else 'disabled' }}
    - name: chargen-stream
    - enable: {{ 'True' if pillar.get('enable_chargen-stream', false)  else 'False' }}
    - sig: chargen-stream

## 2.1.14 Disable daytime-dgram
daytime-dgram:
  service:
    - {{ 'running' if pillar.get('enable_daytime-dgram', false)  else 'disabled' }}
    - name: daytime-dgram
    - enable: {{ 'True' if pillar.get('enable_daytime-dgram', false)  else 'False' }}
    - sig: daytime-dgram

## 2.1.15 Disable daytime-stream
daytime-stream:
  service:
    - {{ 'running' if pillar.get('enable_daytime-stream', false)  else 'disabled' }}
    - name: daytime-stream
    - enable: {{ 'True' if pillar.get('enable_daytime-stream', false)  else 'False' }}
    - sig: daytime-stream

## 2.1.16 Disable echo-dgram
echo-dgram:
  service:
    - {{ 'running' if pillar.get('enable_echo-dgram', false)  else 'disabled' }}
    - name: echo-dgram
    - enable: {{ 'True' if pillar.get('enable_echo-dgram', false)  else 'False' }}
    - sig: echo-dgram  
  
## 2.1.17 Disable echo-stream
echo-stream:
  service:
    - {{ 'running' if pillar.get('enable_echo-stream', false)  else 'disabled' }}
    - name: echo-stream
    - enable: {{ 'True' if pillar.get('enable_echo-stream', false)  else 'False' }}
    - sig: echo-stream
    
## 2.1.18 Disable tcpmux-server
tcpmux-server:
  service:
    - {{ 'running' if pillar.get('enable_tcpmux-server', false)  else 'disabled' }}
    - name: tcpmux-server
    - enable: {{ 'True' if pillar.get('enable_tcpmux-server', false)  else 'False' }}
    - sig: tcpmux-server
    
    
#### 3 Special Purpose Services ####
## 3.1 Set Daemon umask
/etc/sysconfig/init:
  file:
    - append
    - text: 'umask 027'
    
## 3.2 Remove X Windows
remove_x_windows:
  file:
    - sed
    - name: /etc/inittab
    - before: 'id:5:initdefault'
    - after: 'id:3:initdefault' 

## 3.3 Disable Avahi Server
avahi-daemon:
  service:
    - {{ 'running' if pillar.get('enable_avahi-daemon', false)  else 'disabled' }}
    - name: avahi-daemon
    - enable: {{ 'True' if pillar.get('enable_avahi-daemon', false)  else 'False' }}
    - sig: avahi-daemon

## 3.4 Disable Print Server - CUPS
cups:
  service:
    - {{ 'running' if pillar.get('enable_cups', false)  else 'disabled' }}
    - name: cups
    - enable: {{ 'True' if pillar.get('enable_cups', false)  else 'False' }}
    - sig: cups
    
## 3.5 Remove DHCP Server 
## Up in package management

## 3.6 Configure Network Time Protocol (NTP)    
ntpd:
  service:
    - running
    - required:
      - file: /etc/ntp.conf
    - name: ntpd
    - enable: True
    - sig: ntpd
    - watch:
      - file: /etc/ntp.conf
      - file: /etc/sysconfig/ntpd
      
# Manage the ntp config file      
/etc/ntp.conf:
  file:                               
    - managed       
    - source: salt://cis/files/etc.ntp.conf
    - mode: 644
    - template: jinja
 
# Make sure that the daemon is running as an unprivileged user:    
/etc/sysconfig/ntpd:
  file:                               
    - managed       
    - source: salt://cis/files/etc.sysconfig.ntpd
    - mode: 644
    - template: jinja     

## 3.7 Remove LDAP 
## Up in package management

## 3.8 Disable NFS and RPC
{% for service in ['nfslock', 'rpcgssd', 'rpcbind', 'rpcidmapd', 'rpcsvcgssd'] %} 
{{service}}:
  service:
    - {{ 'running' if pillar.get('enable_nfs', false)  else 'disabled' }}
    - name: {{service}}
    - enable: {{ 'True' if pillar.get('enable_nfs', false)  else 'False' }}
{% endfor %}

## 3.9 Remove DNS Server (bind)
## 3.10 Remove FTP Server (vsftp)
## 3.11 Remove HTTP Server (httpd)
## 3.12 Remove Dovecot (IMAP and POP3 services) (dovecot)
## 3.13 Remove Samba (samba)
## 3.14 Remove HTTP Proxy Server (squid)
## 3.15 Remove SNMP Server (net-snmp)
## Up in package management

## 3.16 Configure Mail Transfer Agent for Local-Only Mode
## TODO

#### 4 Network Configuration and Firewalls ####
## 4.1.1 Disable IP Forwarding 
## Check for hypervisor, and enable fwding if the node has one.
net.ipv4.ip_forward:
  sysctl:
    - present
    # Test for salt.virt module first, to prevent 
    # the "virt.is_hyper" is not available error.
    {% if 'virt.is_hyper' in salt and salt['virt.is_hyper'] %}
    - value: 1
    {% else %}
    - value: 0
    {% endif %}

## 4.1.2 Disable Send Packet Redirects
net.ipv4.conf.all.send_redirects:
  sysctl:
    - present
    - value: 0
    
net.ipv4.conf.default.send_redirects:
  sysctl:
    - present
    - value: 0
    
## 4.2.1 Disable Source Routed Packet Acceptance
net.ipv4.conf.all.accept_source_route:
  sysctl:
    - present
    - value: 0
    
net.ipv4.conf.default.accept_source_route:
  sysctl:
    - present
    - value: 0
    
## 4.2.2 Disable ICMP Redirect Acceptance
net.ipv4.conf.all.accept_redirects:
  sysctl:
    - present
    - value: 0
  
net.ipv4.conf.default.accept_redirects:
  sysctl:
    - present
    - value: 0

## 4.2.3 Disable Secure ICMP Redirect Acceptance
net.ipv4.conf.all.secure_redirects:
  sysctl:
    - present
    - value: 0
    
net.ipv4.conf.default.secure_redirects:
  sysctl:
    - present
    - value: 0

## 4.2.4 Log Suspicious Packets 
net.ipv4.conf.all.log_martians:
  sysctl:
    - present
    - value: 1

net.ipv4.conf.default.log_martians:
  sysctl:
    - present
    - value: 1

## 4.2.5 Enable Ignore Broadcast Requests
net.ipv4.icmp_echo_ignore_broadcasts:
  sysctl:
    - present
    - value: 1

## 4.2.6 Enable Bad Error Message Protection
net.ipv4.icmp_ignore_bogus_error_responses:
  sysctl:
    - present
    - value: 1

## 4.2.7 Enable RFC-recommended Source Route Validation
net.ipv4.conf.all.rp_filter:
  sysctl:
    - present
    - value: 1
net.ipv4.conf.default.rp_filter:
  sysctl:
    - present
    - value: 1

## 4.2.8 Enable TCP SYN Cookies 
net.ipv4.tcp_syncookies:
  sysctl:
    - present
    - value: 1

## 4.3.1 Deactivate Wireless Interfaces (Not implemented)

## 4.4 Disable IPv6    
## 4.4.1.1 Disable IPv6 Router Advertisements
net.ipv6.conf.all.accept_ra:
  sysctl:
    - present
    - value: 0
    
net.ipv6.conf.default.accept_ra:
  sysctl:
    - present
    - value: 0

## 4.4.1.2 Disable IPv6 Redirect Acceptance (Not Scored)
net.ipv6.conf.all.accept_redirects:
  sysctl:
    - present
    - value: 0  

net.ipv6.conf.default.accept_redirects:
  sysctl:
    - present
    - value: 0

## 4.4.2 Disable IPv6 
# disable ipv6 support in the kernel -- from Red Hat:
net.ipv6.conf.all.disable_ipv6:
  sysctl:
    - present
    - value: {{ '0' if pillar.get('enable_ipv6', false)  else '1' }}
    
net.ipv6.conf.default.disable_ipv6:
  sysctl:
    - present
    - value: {{ '0' if pillar.get('enable_ipv6', false) else '1' }}
    
# from CIS
{% if pillar.get('enable_ipv6', false) %}
ipv6_sysconfig_network_enable:
  file:
    - sed
    - name: /etc/sysconfig/network
    - before: '^NETWORKING_IPV6=.*'
    - after: ''
    - options: '-r -e "/^NETWORKING_IPV6.*/d"'

{% else %}
ipv6_syconfig_network_disable: 
  file:
    - append
    - name: /etc/sysconfig/network 
    - text: "NETWORKING_IPV6=no"
{% endif %}

{% if pillar.get('enable_ipv6', false) %}
ipv6_sysconfig_network_enable2:
  file:
    - sed
    - name: /etc/sysconfig/network
    - before: '^IPV6INIT.*'
    - after: ''
    - options: '-r -e "/^IPV6INIT.*/d"'

{% else %}
ipv6_syconfig_network_disable2: 
  file:
    - append
    - name: /etc/sysconfig/network 
    - text: "IPV6INIT=no"
{% endif %}

/etc/modprobe.d/ipv6.conf:
  file:
    - managed
    - source: salt://cis/files/etc.modprobe.d.ipv6.conf
    - mode: 644
    - template: jinja

## 4.5.1 Install TCP Wrappers 
## Up in package management 

## 4.5.2 Create /etc/hosts.allow
## 4.5.3 Verify Permissions on /etc/hosts.allow
/etc/hosts.allow:
  file:                               
    - managed       
    - source: salt://cis/files/etc.hosts.allow
    - mode: 644
    - template: jinja
    
## 4.5.4 Create /etc/hosts.deny
## 4.5.5 Verify Permissions on /etc/hosts.deny
/etc/hosts.deny:
  file:                               
    - managed       
    - source: salt://cis/files/etc.hosts.deny
    - mode: 644
    - template: jinja    
    
#### 4.6 Uncommon Network Protocols
## 4.6.1 Disable DCCP
## 4.6.2 Disable SCTP
## 4.6.3 Disable RDS 
## 4.6.4 Disable TIPC     
/etc/modprobe.d/CIS.conf:
  file:                               
    - managed       
    - source: salt://cis/files/etc.modprobe.d.cis.conf
    - mode: 644
    - template: jinja
 
## 4.7 Enable IPtables
iptables:
  service:
    - {{ 'disabled' if pillar.get('disable_iptables', false)  else 'running' }}
    - name: iptables
    - enable: {{ 'False' if pillar.get('disable_iptables', false)  else 'True' }}
    
## 4.8 Enable IP6tables 
ip6tables:
  service:
    - name: ip6tables
    {% if pillar['enable_ipv6'] == 'yes' %}
    - running
    - enable: True
    {% else %} 
    - disabled
    - enable: False  
    {% endif %}
    
    
#### 5 Logging and Auditing
## 5.1.1 Install the rsyslog package (Scored)
## Up in package management

## 5.1.2 Activate the rsyslog Service (Scored)
# It is important to ensure that syslog is turned off so that it does
# not interfere with the rsyslog service.
syslog:
  service:
    - disabled
    - name: syslog
    - enable: False
    
rsyslog:
  service:
    - running
    - required:
      - file: /etc/rsyslog.conf
    - name: rsyslog
    - enable: True
    - sig: rsyslogd
    - watch:
      - file: /etc/rsyslog.conf

## 5.1.3 Configure /etc/rsyslog.conf
/etc/rsyslog.conf:
  file:                               
    - managed       
    - source: salt://cis/files/etc.rsyslog.conf
    - mode: 644
    - template: jinja 
    
## 5.1.4 Create and Set Permissions on rsyslog Log Files
## Currently using pillar to identify all the log files:
{% for file in ['kern.log', 'messages', 'daemon.log', 'syslog',
'unused', 'secure', 'mailog', 'cron', 'spooler', 'boot.log'] %}
/var/log/{{file}}:
  file:
    - managed
    - mode: 600
    - user: root
    - group: root 
{% endfor %}

## 5.1.5 Configure rsyslog to Send Logs to a Remote Log Host
## There is a pillar['rsyslog_server'] variable to configure this
## if present it will be added the the rsyslog.conf file.

## 5.1.6 Accept Remote rsyslog Messages Only on Designated Log Hosts (Not implemented)

#### 5.2 Configure System Accounting (auditd)
## 5.2.1.1 Configure Audit Log Storage Size
## 5.2.1.2 Disable System on Audit Log Full 
## 5.2.1.3 Keep All Auditing Information 
/etc/audit/auditd.conf:
  file:                               
    - managed       
    - source: salt://cis/files/etc.audit.auditd.conf
    - user: root
    - group: root
    - mode: 640
    - template: jinja 
    
## 5.2.2 Enable auditd Service
auditd:
  service:
    - running
    - required:
      - file: /etc/audit/auditd.conf
      - file: /etc/audit/audit.rules
    - name: auditd
    - enable: True
    - sig: auditd
    - watch:
      - file: /etc/audit/auditd.conf
      - file: /etc/audit/audit.rules

## 5.2.3 Enable Auditing for Processes That Start Prior to auditd (Scored)
## TODO 

## 5.2.4 Record Events That Modify Date and Time Information 
## 5.2.5 Record Events That Modify User/Group Information (Scored)
## 5.2.6 Record Events That Modify the System's Network Environment
## 5.2.7 Record Events That Modify- sig: nfslock the System's Mandatory Access Controls (Scored)
#5.2.8 Collect Login and Logout Events (Scored)
#5.2.9 Collect Session Initiation Information (Scored)
#5.2.10 Collect Discretionary Access Control Permission Modification Events (Scored)
#5.2.11 Collect Unsuccessful Unauthorized Access Attempts to Files (Scored)
#5.2.12 Collect Use of Privileged Commands (Scored)
#5.2.13 Collect Successful File System Mounts (Scored)
#5.2.14 Collect File Deletion Events by User (Scored)
#5.2.15 Collect Changes to System Administration Scope (sudoers) (Scored)
#5.2.16 Collect System Administrator Actions (sudolog) (Scored)
#5.2.17 Collect Kernel Module Loading and Unloading (Scored)
#5.2.18 Make the Audit Configuration Immutable (Scored)
/etc/audit/audit.rules:
  file:                               
    - managed
    {% if grains['cpuarch'] == 'x86_64' %}     
    - source: salt://cis/files/etc.audit.audit.rules64
    {% else %}
    - source: salt://cis/files/etc.audit.audit.rules32
    {% endif %}
    - mode: 0640
    - template: jinja    
  
## 5.3 Configure logrotate (Not Scored)
/etc/logrotate.d/syslog:
  file:
    - managed
    - source: salt://cis/files/etc.logrotate.d.syslog
    - mode: 644
    - template: jinja

#### 6 System Access, Authentication and Authorization
## 6.1.1 Enable anacron Daemon (Scored)
## Up in package management

## 6.1.2 Enable crond Daemon (Scored)
crond:
  service:
    - running
    - name: crond
    - enable: True
    - sig: crond
    
## 6.1.3 Set User/Group Owner and Permission on /etc/anacrontab
/etc/anacrontab:
  file:
    - managed
    - mode: 0600
    - user: root
    - group: root
    
## 6.1.4 Set User/Group Owner and Permission on /etc/crontab (Scored)
/etc/crontab:
  file:
    - managed
    - mode: 0600
    - user: root
    - group: root
    
## 6.1.5 Set User/Group Owner and Permission on /etc/cron.hourly
/etc/cron.hourly:
  file.directory:
    - mode: 0700
    - user: root
    - group: root

## 6.1.6 Set User/Group Owner and Permission on /etc/cron.daily (Scored)
/etc/cron.daily:
  file.directory:
    - mode: 0700
    - user: root
    - group: root

## 6.1.7 Set User/Group Owner and Permission on /etc/cron.weekly
/etc/cron.weekly:
  file.directory:
    - mode: 0700
    - user: root
    - group: root
    
## 6.1.8 Set User/Group Owner and Permission on /etc/cron.monthly
/etc/cron.monthly:
  file.directory:
    - mode: 0700
    - user: root
    - group: root

## 6.1.9 Set User/Group Owner and Permission on /etc/cron.d (Scored)
/etc/cron.d:
  file.directory:
    - mode: 0700
    - user: root
    - group: root

## 6.1.10 Restrict at Daemon (Scored)
/etc/at.deny:
  file:
    - absent

/etc/at.allow:
  file.directory:
    - mode: 0700
    - user: root
    - group: root
    
## 6.1.11 Restrict at/cron to Authorized Users
/etc/cron.deny:
  file:
    - absent

/etc/cron.allow:
  file:
    - managed
    - source: salt://cis/files/etc.cron.allow
    - mode: 0600
    - user: root
    - group: root
    - template: jinja

#### 6.2 Configure SSH
## 6.2.1 Set SSH Protocol to 2 (Scored)
## 6.2.2 Set LogLevel to INFO (Scored)
## 6.2.4 Disable SSH X11 Forwarding (Scored)
## 6.2.5 Set SSH MaxAuthTries to 4 or Less (Scored)
## 6.2.6 Set SSH IgnoreRhosts to Yes (Scored)
## 6.2.8 Disable SSH Root Login (Scored)
## 6.2.9 Set SSH PermitEmptyPasswords to No (Scored)
## 6.2.11 Use Only Approved Cipher in Counter Mode (Scored)
## 6.2.12 Set Idle Timeout Interval for User Login (Scored)
## 6.2.13 Limit Access via SSH (Scored)    
sshd:
  service:
    - running
    - required:
      - file: /etc/ssh/sshd_config
    - name: sshd
    - enable: True
    - sig: sshd
    - watch:
      - file: /etc/ssh/sshd_config

/etc/ssh/sshd_config:
  file:                               
    - managed       
    - source: salt://cis/files/etc.ssh.sshd_config
    - mode: 600
    - user: root
    - group: root
    - template: jinja

## 6.2.14 Set SSH Banner (Scored)
## The Banner parameter specifies a file whose contents must be sent to the remote user
## before authentication is permitted. By default, no banner is displayed.    
## /etc/issue file management at 8.1 

#### 6.3 Configure PAM
## 6.3.1 Upgrade Password Hashing Algorithm to SHA-512 (Scored)
## This is only an evaluation script:
pam_hash_test:  
  cmd.run:
    - name: /opt/cis/scripts/6.3.1.all.pam.password.hashing.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/6.3.1.all.pam.password.hashing.sh
    - watch:
      - file.recourse: /opt/cis/scripts         

## 6.3.2 Set Password Creation Requirement Parameters Using pam_cracklib (Scored)
## 6.3.3 Set Strong Password Creation Policy Using pam_passwdqc (Scored)
## 6.3.4 Set Lockout for Failed Password Attempts (Not Scored)
## 6.3.6 Limit Password Reuse (Scored)
/etc/pam.d/system-auth:
  file:
    - managed
    - source: salt://cis/files/etc.pam.d.system-auth
    - mode: 644
    - user: root
    - group: root
    - template: jinja

/etc/pam.d/password-auth:
  file:
    - managed
    - source: salt://cis/files/etc.pam.d.password-auth
    - mode: 644
    - user: root
    - group: root
    - template: jinja
      
## 6.3.5 Use pam_deny.so to Deny Services (Not Scored)
/etc/pam.d/sshd:
  file:
    - managed
    - source: salt://cis/files/etc.pam.d.sshd
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    
## 6.4 Restrict root Login to System Console (Not Scored)
/etc/securetty:
  file.sed:
    - before: '^vc'
    - after: ''
    - options: '-r -e "/^vc/d"'
    
## 6.5 Restrict Access to the su Command (Scored)
/etc/pam.d/su:
  file:
    - managed
    - source: salt://cis/files/etc.pam.d.su
    - mode: 644
    - user: root
    - group: root       
    - template: jinja

#### 7 User Accounts and Environment
## 7.1.1 Set Password Expiration Days (Scored)
/etc/login.defs:
  file:
    - managed
    - source: salt://cis/files/etc.login.defs
    - mode: 644
    - user: root
    - group: root       
    - template: jinja


## 7.2 Disable System Accounts (Scored)
system_accounts_test:  
  cmd.run:
    - name: /opt/cis/scripts/7.2.disable.system.accounts.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/7.2.disable.system.accounts.sh
    - watch:
      - file.recourse: /opt/cis/scripts

## 7.3 Set Default Group for root Account (Scored)
root_primary_group_test:  
  cmd.run:
    - name: /opt/cis/scripts/7.3.default.group.for.root.account.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/7.3.default.group.for.root.account.sh
    - watch:
      - file.recourse: /opt/cis/scripts
               
## 7.4 Set Default umask for Users (Scored)
umask_bashrc_sed:
  file:
    - sed
    - name: /etc/bashrc
    - before: umask 002  
    - after: umask 077

umask_bashrc_sed2:    
  file:
    - sed
    - name: /etc/bashrc
    - before: umask 022
    - after: umask 077
    
umask_profile_sed:
  file:
    - sed
    - name: /etc/profile
    - before: umask 002  
    - after: umask 077

umask_profile_sed2:    
  file:
    - sed
    - name: /etc/profile
    - before: umask 022
    - after: umask 077
    
## 7.5 Lock Inactive User Accounts (Scored)
{% set locked = salt['cmd.run']('useradd -D | grep INACTIVE') %}
{% if locked == 'INACTIVE=-1' %}
change_locked:
  cmd.run:
    - name: 'useradd -D -f 35'
{% endif%}

#### 8 Warning Banners
## 8.1 Set Warning Banner for Standard Login Services (Scored)
{% for file in ['motd', 'issue', 'issue.net'] %}
/etc/{{file}}:
  file:
    - managed
    - source: salt://cis/files/etc.{{file}}
    - mode: 644
    - user: root
    - group: root
    - template: jinja 
{% endfor %}
      
      
#### 9 System Maintenance
## 9.1.1 Verify System File Permissions (Not Scored)
## 9.1.2 Verify Permissions on /etc/passwd (Scored)
## 9.1.3 Verify Permissions on /etc/shadow (Scored)
## 9.1.5 Verify Permissions on /etc/group (Scored)
## 9.1.6 Verify User/Group Ownership on /etc/passwd (Scored)
## 9.1.7 Verify User/Group Ownership on /etc/shadow (Scored)
## 9.1.9 Verify User/Group Ownership on /etc/group (Scored)
{% for file, filemode in  [ ('passwd', 644 ), ('shadow', 000), ('gshadow', 000), ('group', 644) ] %}
/etc/{{file}}:
  file:
    - managed
    - mode: {{filemode}}
    - user: root
    - group: root
{% endfor %}

## 9.1.10 Find World Writable Files (Not Scored)
word_writable_files:  
  cmd.run:
    - name: /opt/cis/scripts/9.1.10.find.world.writable.files.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/9.1.10.find.world.writable.files.sh
    - watch:
      - file.recourse: /opt/cis/scripts
               
## 9.1.11 Find Un-owned Files and Directories (Scored)
unowned_files:  
  cmd.run:
    - name: /opt/cis/scripts/9.1.11.find.unowned.files.and.directories.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/9.1.11.find.unowned.files.and.directories.sh             
    - watch:
      - file.recourse: /opt/cis/scripts
      
## 9.1.12 Find Un-grouped Files and Directories (Scored)
ungroup_files:  
  cmd.run:
    - name: /opt/cis/scripts/9.1.12.find.ungrouped.files.and.directories.sh
    - cwd: /
    - stateful: True
    - required:
         -file: /opt/cis/scripts/9.1.12.find.ungrouped.files.and.directories.sh
    - watch:
      - file.recourse: /opt/cis/scripts
               
## 9.1.13 Find SUID System Executables (Not Scored)
## 9.1.14 Find SGID System Executables (Not Scored)
## Currently Not implemented: Requires manual review

#### 9.2 Review User and Group Settings
## 9.2.1 Ensure Password Fields are Not Empty (Scored)
## 9.2.2 Verify No Legacy "+" Entries Exist in /etc/passwd File (Scored)
## 9.2.3 Verify No Legacy "+" Entries Exist in /etc/shadow File (Scored)
## 9.2.4 Verify No Legacy "+" Entries Exist in /etc/group File (Scored)
## 9.2.5 Verify No UID 0 Accounts Exist Other Than root (Scored)
## 9.2.6 Ensure root PATH Integrity (Scored)
## 9.2.7 Check Permissions on User Home Directories (Scored)
## 9.2.8 Check User Dot File Permissions (Scored)
## 9.2.9 Check Permissions on User .netrc Files (Scored)
## 9.2.10 Check for Presence of User .rhosts Files (Scored)
## 9.2.11 Check Groups in /etc/passwd (Scored)
## 9.2.12 Check That Users Are Assigned Home Directories (Scored)
## 9.2.13 Check That Defined Home Directories Exist (Scored)
## 9.2.14 Check User Home Directory Ownership (Scored)
## 9.2.15 Check for Duplicate UIDs (Scored)
## 9.2.16 Check for Duplicate GIDs (Scored)
## 9.2.17 Check That Reserved UIDs Are Assigned to System Accounts (Scored)
## 9.2.18 Check for Duplicate User Names (Scored)
## 9.2.19 Check for Duplicate Group Names (Scored)
## 9.2.20 Check for Presence of User .netrc Files (Scored)
## 9.2.21 Check for Presence of User .forward Files (Scored)
## TODO
         
## endif of grains['os_family'] == 'RedHat'
{% endif %}
