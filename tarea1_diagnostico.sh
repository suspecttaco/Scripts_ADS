#!/bin/bash
# Mostar Hostname, IP y espacio en el disco.

echo "Hostname: $(hostname)"

echo -e "IP's: "
ip -4 addr
echo ""

echo -e "Espacio en el disco: "
df -h
echo ""