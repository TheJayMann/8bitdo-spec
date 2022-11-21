#!/bin/bash

# need to enable lastpipe so piping to `readarray` works
shopt -s lastpipe;

exec 5<> $1;

echo Writing configuration
# Need to break the binary config file into sections of 45 bytes, so they fit in the write request packet
for offset in {0..1651..45}
do
  size=$((1652 - offset))
  if [[ size -gt 45 ]];
  then size=45;
  fi
  echo $offset $size
  printf -v offsetl '\\%o' $((offset & 0xff));
  printf -v offseth '\\%o' $((offset >> 8));
  printf -v packetsize '\\%o' $((size + 17));
  printf -v sizeb '\\%o' $size;
  {
    printf "\201$packetsize\4\1\0\0\0$sizeb\0\0\0\164\6\0\0$offsetl$offseth\0\0";
    head -c $((offset + size)) $2 | tail -c $size;
    if [[ size -lt 45 ]];
    then for ((pad = 45 - size ; pad > 0 ; pad--)); do printf '\0'; done
    fi
  #} | dd bs=64c | hexdump -vC;
  } | tee >(hexdump -vC >&2) | dd bs=64c iflag=fullblock count=1 >&5;

  # initialize resp to a value which will not match as bash loops do not have post condition loops
  resp=(0 0 0 0 0 0 0 0 0)
  # the response should begin with 02 04 04 00 01 00, then have the written size, full size, and current offset
  until [ "${resp[*]}" == "1026 4 1 $size 0 1652 0 $offset 0" ]; do
    echo Reading response...
    #Need to read the 64 byte buffer, but only the first 18 bytes matter
    head -c 64 <&5 | tee >(hexdump -vC >&2) | head -c 18 | hexdump -v -e '/2 "%d\n"' | readarray -t resp
  done
  echo
done;

echo Finalizing configuration

# final step is to finalize the config writing by sending a 6 command, 21 sub command
#printf "\201\21\4\6\0\25\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" | hexdump -vC;
printf "\201\21\4\6\0\25\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" | tee >(hexdump -vC >&2) >&5;

# initialize resp to a value which will not match as bash loops do not have post condition loops
resp=(0 0 0)
# the response should begin with 02 04 04 00 06 00, the rest of the response does not matter
until [ "${resp[*]}" == "1026 4 6" ]; do
  echo Reading response...
  #Need to read the 64 byte buffer, but only the first 6 bytes matter
  head -c 64 <&5 | tee >(hexdump -vC >&2) | head -c 6 | hexdump -v -e '/2 "%d\n"' | readarray -t resp
done

echo Complete

exec 5>&-;
