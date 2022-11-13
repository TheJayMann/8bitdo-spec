#!/bin/bash

exec 5<> $1;
printf "\1\146\252\0\41\1" > $1;
head -c 64 <&5 | hexdump -C;
printf "\1\146\252\0\41\1" > $1;
head -c 64 <&5 | hexdump -C;
exec 5>&-;