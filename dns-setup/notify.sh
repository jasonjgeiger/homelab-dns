#!/bin/bash
# keepalived notify hook; $1 = MASTER | BACKUP | FAULT
ROLE="${1:-unknown}"
if command -v logger >/dev/null 2>&1; then
  logger -t keepalived-pihole "Pi-hole VRRP: ${ROLE}"
fi
