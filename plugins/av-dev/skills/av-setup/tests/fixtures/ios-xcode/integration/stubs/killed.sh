#!/usr/bin/env bash
# stub: killed by a signal after printing part of a JSON object
printf '{"adapter": "ios-xcode", "schema_version": 1, "comp'
kill -9 $$
