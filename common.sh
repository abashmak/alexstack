#!/usr/bin/env bash

if [ -z ${MY_PRIVATE_IP+x} ]; then
    nic=`ls -og /sys/class/net | grep -v virtual | awk '{print $7}' | tr '\n' ' '`
    export MY_PRIVATE_IP=`ip a | grep $nic'$' | awk '{print $2}' | awk -F'/' '{print $1}'`
fi
if [ -z ${MY_PUBLIC_IP+x} ]; then
  if [ -z ${1+x} ]; then
    echo "Public IP not set and not provided, using private IP"
    export MY_PUBLIC_IP=$MY_PRIVATE_IP
  fi
fi

release=`lsb_release -c | awk '{print $2}'`
