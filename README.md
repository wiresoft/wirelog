# wirelog
Bare-bones MacOS syslog host. Accepts input on UDP port 514, parses input by regular expression, and logs result using MacOS unified logging (os_log). MacOS 10.14 or later only.

# installation
To use as a syslog daemon, perform the following steps from the *install* directory:
1. sudo cp com.wireframesoftware.wirelog.plist to /Library/Launchdaemons/com.wireframesoftware.wirelog.plist
2. sudo chown root:wheel /Library/LaunchDaemons/com.wireframesoftware.wirelog.plist
3. mkdir /usr/local/etc/wirelog
4. cp wirelog.conf /usr/local/etc/wirelog/wirelog.conf
5. cp wirelogd /usr/local/bin/wirelogd
6. chmod +x /usr/local/bin/wirelogd
7. sudo chown -R root:staff /usr/local/etc/wirelog
8. sudo chown root:staff /usr/local/etc/wirelog/wirelog.conf

# configuration
The wirelog.conf file consists of FORMAT...ENDFORMAT sections which specify how to interpret remote logs, followed by a list of IPv4 or IPv6 addresses of log clients whose input will be interpreted according to the preceeding FORMAT block. Instead of IP addresses, a "\*" character can be used to define the *default* format for clients not specified in the conf file. 

The first line of the FORMAT block is a regular expression which is matched against each log message from the listed clients. The subsequent lines within the format block contain keywords which determine how each capture expression in the regex is to be used:
- `host` : Subexpression is the name of the log host. This will be used as the os_log `subsystem` in the form `local.host`
- `category` : Subexpression will be used as the os_log `category`
- `timestamp` : Subexpression will be appended to the message as the client-local timestamp. This is sometimes useful to see if logging clients have different time setting from the syslog host.
- `message` : Subexpression is the content of the log message.
