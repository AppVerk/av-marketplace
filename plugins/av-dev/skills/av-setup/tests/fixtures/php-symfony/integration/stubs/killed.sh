#!/usr/bin/env bash
# Stub: the process dies from SIGKILL after printing partial output.
printf '{"adapter":"php-symfony","schema_version":1,'
kill -KILL $$
