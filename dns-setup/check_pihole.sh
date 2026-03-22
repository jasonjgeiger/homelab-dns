#!/bin/bash
# Simple DNS query check inside the container
dig @127.0.0.1 google.com +short > /dev/null 2>&1
if [ $? -eq 0 ]; then
  exit 0
else
  exit 1
fi
