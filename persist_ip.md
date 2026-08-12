

nano persist-ip.sh

Paste the script, then:

chmod +x persist-ip.sh
sudo ./persist-ip.sh

## SAMPLE OUTPUT



====================================================
 Ubuntu ESXi VM - Persistent Static IP Setup
====================================================

Detected OS : Ubuntu 22.04.5 LTS

Supported Ubuntu version detected: 22.04

====================================================
 CURRENT NETWORK CONFIGURATION
====================================================

Ubuntu    : 22.04
Interface : ens160
IP        : 192.168.1.203/24
Gateway   : 192.168.1.1
DNS       : 192.168.1.1,192.168.1.169
MAC       : 00:0c:29:69:94:f8

====================================================

Checking existing network...
Gateway reachable: YES

Creating backup...

Backup:
/root/netplan-backup-20260812-092617

Validating Netplan...
Netplan syntax: OK

====================================================
 TESTING NEW CONFIGURATION
====================================================

Temporary Netplan test starting...

Timeout: 30 seconds

Test 1: Checking IP address...
  PASS - IP address correct.

Test 2: Checking default route...
  PASS - Gateway correct.

Test 3: Checking gateway...
  PASS - Gateway responding.

Test 4: Checking Internet connectivity...
  PASS - Internet reachable.

Test 5: Checking DNS...
  PASS - DNS working.

====================================================
 TEST RESULTS
====================================================

IP Address       : 1
Default Route    : 1
Gateway Ping     : 1
Internet         : 1
DNS              : 1

ALL REQUIRED TESTS PASSED.

Accepting Netplan configuration...

====================================================
 SUCCESS
====================================================

Static IP configuration has been accepted.

Persistent IP:

    192.168.1.203

NO REBOOT REQUIRED.

The same IP will be used after future reboots.

Backup:

    /root/netplan-backup-20260812-092617
