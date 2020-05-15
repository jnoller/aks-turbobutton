#!/usr/bin/env bash

targ=$1
cd "${targ}" || exit 1
wget -qO- https://wordpress.org/latest.tar.gz | tar xvz -C ./wp
