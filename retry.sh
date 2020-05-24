#!/bin/bash

retry_count=$1
shift
sleep_time=$1
shift

exit_code=1
while [ $retry_count -ge 0 ]; do
	echo $retry_count;
	$@
	exit_code=$?
	if [ $exit_code -eq 0 ]; then
		exit 0;
	fi
	sleep $sleep_time
	retry_count=$(($retry_count - 1))
done
exit $exit_code;
