#!/bin/bash

> $2;
exec 5<> $1;
for offset in {0..1651..45}
do
  size=$((1652 - offset))
  if [[ size -gt 45 ]];
  then size=45;
  fi
  printf -v offsetl '\\%o' $((offset & 0xff))
  printf -v offseth '\\%o' $((offset >> 8))
  printf -v packetsize '\\%o' $((size + 17));
  printf -v sizeb '\\%o' $size;

  echo Sending Packet
  printf "\201$packetsize\4\2\0\0\0$sizeb\0\0\0\164\6\0\0$offsetl$offseth\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" | tee >(hexdump -vC >&2) >&5;
  echo Receiving Packet
  dd bs=64c iflag=fullblock count=1 <&5 | tee >(hexdump -vC >&2) | head -c $((size + 18)) |  tail -c $size >> $2;
  echo
done;
exec 5>&-;
