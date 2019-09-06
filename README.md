# wirelog
Bare-bones MacOS syslog host. Accepts input on UDP port 514, parses input by regular expression, and logs result using MacOS unified logging (os_log).

To use as a syslog daemon, perform the following steps from the #install# directory:
1. sudo cp com.wireframesoftware.wirelog.plist to /Library/Launchdaemons/com.wireframesoftware.wirelog.plist
2. sudo chown root:wheel /Library/LaunchDaemons/com.wireframesoftware.wirelog.plist
3. mkdir /usr/local/etc/wirelog
4. cp wirelog.conf /usr/local/etc/wirelog/wirelog.conf
5. cp wirelogd /usr/local/bin/wirelogd
6. chmod +x /usr/local/bin/wirelogd
7. sudo chown -R root:staff /usr/local/etc/wirelog
8. sudo chown root:staff /usr/local/etc/wirelog/wirelog.conf

