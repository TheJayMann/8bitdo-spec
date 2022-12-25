# 8bitdo SN30 Pro+

## Request packet format
All requests made to the SN30 Pro+ controller consist of a three byte header, a 16 byte request, and up to 45 bytes of
data.

The header consists of a one byte value of hex `81`, followed by a one byte value indicating the total byte size of the
packet, not including the intial byte, ending with a one byte value indicating the section used, which is `4` when
operating on configuration data.  This is identical to the Pro2 request packet header.

The 16 byte request consist of various values.  The request type is a one byte value located at offset `0`, and an
optional 4 byte little endian encoded value, which might indicate subtype or parameter value is located at offset `4`.
A request type of `1` indicates writing configuration data, and a request type of 2 indicates reading configuration
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
WIP

## Read configuration
WIP

## Write configuration
WIP


# Configuration Binary Format
WIP