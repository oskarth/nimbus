#!/bin/sh

../env.sh nim c --opt:speed --lineTrace:off status_api
gcc status_api.c ./libnimbus_api.a -lm -o xx

./xx

