#!/bin/bash

> $2;
exec 5<> $1;
for offset in {0..1651..28}
do
  printf -v offsetl '\\%o' $((offset & 0xff))
  printf -v offseth '\\%o' $((offset >> 8))
  printf "\201\76\4\2\0\0\0\34\0\0\0\164\6\0\0$offsetl$offseth\0\0" >&5;
  head -c 46 <&5 | tail -c 28 >> $2;
done;
exec 5>&-;