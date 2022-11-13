# 8bitdo Pro2
Based on analysis of the 8BitDoAdvance.dll export table, a read, write, current slot, and CRC function are shared with Pro2, Ultimate2_4, UltimateBT, and Ultimate_PC.  This would indicate that all of these devices are treated the same, and share an identical protocol.  However, further analysis of these individual functions indicate that specific PID values have slight variations in the protocol.  The only device I have to test with this is an older Pro2 model (PID 0x6003), which does not have any variations to the protocol.  This folder will document my findings with this specific model of controller.

## Request format
All requests made to the Pro2 controller consist of a three byte header, a 16 byte request, and up to 45 bytes of data.

The three byte header starts first with the hex value `81`, which, according to HID documentation, should represent the report number being used.  I have not been able to read the report descriptors for the device, and cannot determine if this is an actual report number or not.  This does happen to match the input endpoint address, though perhaps coincidentally. The second byte of the header appears to be the size of the buffer to be used to read the response data.  Given that the device specifies a packet size of 64, this should be equal to or less than this value.  The third byte appears to be a magic value of `4`.  Given that the response buffer size is typically (perhaps always) 63, the header will typically contain `81 3E 04`.

For the request, the first four bytes appear to be the request type, in little endian. After this is followed by a two byte little endian value indicating the amount of data requested, a two byte value left as zero for the Pro2 (6003) model, a four byte little endian value for the total size of the data, and a four byte little endian value for the offset of the current request. 

## Get current slot
The current slot number is part of the configuration data, a two byte value offset 18 bytes.  As a shortcut to not have to load the entire configuration, this value can be obtained by reading just the first 20 bytes, then obtaining the last two bytes.

## Read configuration
The read configuration request command has a value of `2`.  The size of the configuration data is 1652 bytes.  The packet size is 64 bytes, and the response header size is 18 bytes.  If allowing an extra byte at the end for a null terminating packet, this allows each read packet to contain 45 bytes of data.  The most efficient way to load the entire configuration would be to read it 45 bytes at a time, with the final pass reading the remaning amount (32 bytes), for a total of 37 packets.  A typical request will look like the following, where `OL` represents the low byte of the current offset, and `OH` represents the high byte of the current offset, where the offset is restricted to a two byte value.
```
81 3E 04
02 00 00 00
2D 00 00 00
74 06 00 00
OL OH 00 00
```
A simpler method which would not require keeping track of how many bytes to read for the final packet would be to instead read 28 bytes at a time.  This would require reading 59 packets, but the final packet would also be 28 bytes, and can work with scripts and programs where determining the final packet size is difficult or impossible.

The response configuration contains an 18 byte header, followed by data.  The first four bytes appear to be the magic value 0x40402, encoded little endian.  The next two byte value is the low word of the command used, little endian encoded, in the case of reading the configuration data is `2`.  The next two byte value is the little endian encoded value of the size of the data in the response.  The next 10 bytes appear to be ignored.  Following this header is the section of the configuration data, determined by the offset and size specified in the request.

The script diReadPro2.sh will repeatedly read portions of the configuration data, then rebuild the configuration data as a 1652 byte binary file.  It reads the data 28 bytes at a time, and ignores the response packet headers.  The first parameter should be the `hidraw` file, and the second parameter should be the filename which will contain the binary configuration data.

## CRC 16
WIP

## Write configuration
WIP