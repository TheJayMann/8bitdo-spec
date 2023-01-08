# 8bitdo SN30 Pro+

As the device I have to test with has a firmware version greater than v3.02, I am only able to test and document the new
SN30 Pro+ protocol.  This documentation does not apply to controllers with firmware version v3.02 or earlier. 

## Request packet format
All requests made to the SN30 Pro+ controller consist of a three byte header, a 16 byte request, and up to 45 bytes of
data.

The header consists of a one byte value of hex `81`, followed by a one byte value indicating the total byte size of the
packet, not including the intial byte, ending with a one byte value indicating the section used, which is `4` when
operating on configuration data.  This is identical to the Pro2 request packet header.

The 16 byte request consist of various values.  The request type is a one byte value located at offset `0`, and an
optional 4 byte little endian encoded value, which might indicate subtype or parameter value is located at offset `4`.
A request type of `1` indicates writing configuration data, and a request type of `2` indicates reading configuration
data.  Neither of these make use of the secondary value.  A value of `6` is used to finalize writing configuration data.
This process has a secondary hex value of `15`.  For reading and writing configuration data, a two byte little endian
encoded value at offset `8` indicates the size of the data in the packet, a two byte little endian encoded value at
offset `10` indicates the total size of the data (`1952`), and a two byte little endian encoded value at offset `12`
indicates the current offset in the configuration data for the current packet data.  While it appears that the Ultimate
Software sets all unused values of the request for a finalizing operation to zero, it does not appear that requests for
reading or writing configuration data is initialized in a consistent manner.  When writing configuration data, the first
request does appear to have all unused data set to zero, but every subsequent request has all unused values set to the
same corresponding values from the first 16 bytes of the previous response packet.  This could likely be caused by
having the request share a buffer with the response packet.  At this time it is unknown to me if the device is checking
that these unused values match the previous values sent in the previous response packet, or if these values are simply
ignored.  When reading configuration data, it appears as though the unused values are set to some arbitrary values, and
these values are used for every request when reading the configuration data.  It is possible that the buffer used to
build these requests was allocated and never initialized, and that it simply contains whatever data was in memory
whenever it was previously allocated.

## Response packet format
Response packets consist of 18 byte response, followed by up to 46 bytes of data.

The first three bytes of the response appear to be the three single byte values of `2`, `4`, `4`.  The next three bytes
appear to be arbitrary data.  The next four bytes represent the little endian encoded value of the operation that was
performed.  This is `1` for writing configuration data, `2` for reading configuration data, and `6` for finalizing
configuration data.  The next single byte value indicates how much data was processed for the current operation.  A
single byte of arbitrary data follows.  The next two double byte values are the little endian encoded values of the
total data size and current data offset of the current operation within the complete operation set.  The final two bytes
contain arbitrary data.

## Read configuration
The read configuration request command has a value of `2` with no secondary value, the size of the configuration is 1952
bytes, and the maximum allowable data packet buffer size between read and write configuration is 45 bytes.  The typical
request and response packet for reading configuration data is represented below, representing unused values as XX, and
the low and high byte of the 2 byte offset values as OL and OH, repsectively.
```
Request (43x loop):
81 3E 04
02 XX XX XX
XX XX XX XX
2D XX A0 07
OL OH XX XX
arbitrary ignored data (45 bytes)

Response (43x loop):
02 04
04 XX XX XX
02 00 00 00
2D XX A0 07
OL OH XX XX
data (45 bytes)

Final request:
81 3E 04
02 XX XX XX
XX XX XX XX
11 XX A0 07
OL OH XX XX
arbitrary ignored data (45 bytes)

Final response:
02 04
04 XX XX XX
02 00 00 00
11 XX A0 07
OL OH XX XX
data (17 bytes)
```

When inspecting the traffic from the Ultimate Software, ignored values (`XX`) from the request packets would contain
arbitrary values, some of which were zero.  Inspecting the code shows that these values were never written when
preparing the packet.  These arbitrary values are likely a result of the memory not being zeroed before being used.  In
my personal testing, setting these unused values to zero worked.  Ingored values in the response packets (`XX`) always
had the value of zero, but these values were never inspected after being loaded into memory.  In addition, the values
for total size and offset are never used, but the values are consistent in the response.

The script <diReadSNProPlus.sh> will repeatedly read portions of the configuration data, then rebuild the configuration data
as a 1952 byte binary file.  The first parameter should be the `hidraw` file, and the second parameter should be the
filename which will contain the binary configuration data.

## Write configuration
WIP


# Configuration Binary Format
WIP