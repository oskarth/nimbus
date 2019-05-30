#!/bin/sh

../env.sh nim c status_api
gcc status_api.c ./libnimbus_api.a -lm -o xx

./xx

