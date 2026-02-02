#!/bin/bash
# Mostar Hostname, IP y espacio en el disco.

echo "Hostname: $(hostname)"

echo -e "IP's : "
ip -4 -o addr show | awk '{print "Interfaz: " $2, "-> IP: " $4}'
echo ""

echo -e "Espacio en el disco: "
df -h --output=source,size,used,avail,pcent | grep "^/dev/"
echo ""
