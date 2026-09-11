#!/bin/bash
set -e

iptables -C DOCKER-USER \
    -m conntrack \
    --ctstate ESTABLISHED,RELATED \
    -j ACCEPT 2>/dev/null || \
iptables -A DOCKER-USER \
    -m conntrack \
    --ctstate ESTABLISHED,RELATED \
    -j ACCEPT

iptables -C DOCKER-USER \
    -p tcp \
    -m conntrack \
    --ctstate NEW \
    --ctorigdstport 80 \
    -j ACCEPT 2>/dev/null || \
iptables -A DOCKER-USER \
    -p tcp \
    -m conntrack \
    --ctstate NEW \
    --ctorigdstport 80 \
    -j ACCEPT

iptables -C DOCKER-USER \
    -p tcp \
    -m conntrack \
    --ctstate NEW \
    --ctorigdstport 443 \
    -j ACCEPT 2>/dev/null || \
iptables -A DOCKER-USER \
    -p tcp \
    -m conntrack \
    --ctstate NEW \
    --ctorigdstport 443 \
    -j ACCEPT

iptables -C DOCKER-USER \
    -j DROP 2>/dev/null || \
iptables -A DOCKER-USER \
    -j DROP
