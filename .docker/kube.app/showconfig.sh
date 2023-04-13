#!/bin/sh

echo -e "\nNginxUnit Config:"
/usr/bin/curl -s -X GET --unix-socket /var/run/control.unit.sock http://localhost/ 2>/dev/null | sed 's/\t/  /g'
