#!/bin/sh

../env.sh nim c status_api
gcc status_api.c ./nimbus_api.a -lm -o xx

./xx

