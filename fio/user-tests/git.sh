#!/usr/bin/env bash

targ=$1
cd "${targ}" || exit 1
/usr/bin/git clone git@github.com:MicrosoftDocs/azure-docs.git >gitlog
