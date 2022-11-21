# 8bitdo Pro2
Based on analysis of the 8BitDoAdvance.dll export table, a read, write, current slot, and CRC function are shared with Pro2, Ultimate2_4, UltimateBT, and Ultimate_PC.  This would indicate that all of these devices are treated the same, and share an identical protocol.  However, further analysis of these individual functions indicate that specific PID values have slight variations in the protocol.  The only device I have to test with this is an older Pro2 model (PID 0x6003), which does not have any variations to the protocol.  This folder will document my findings with this specific model of controller.

## Request packet format
All requests made to the Pro2 controller consist of a three byte header, a 16 byte request, and up to 45 bytes of data.

The three byte header starts first with the hex value `81`, which, according to HID documentation, should represent the report number being used.  I have not been able to read the report descriptors for the device, and cannot determine if this is an actual report number or not.  This does happen to match the input endpoint address, though perhaps coincidentally. The second byte of the header appears to be the size of the buffer to be used to read the response data.  Given that the device specifies a packet size of 64, this should be equal to or less than this value.  The third byte has a value of `4` when operating on configuration data.  Given that the response buffer size is typically (perhaps always) 63, the header will typically contain `81 3E 04`.

For the request, the first four bytes appear to be a two byte request type, followed by a two byte subrequest type, or possibly a request parameter, in little endian.  The value of `1, 0` is to write config data, a value of `2, 0` is to read config data, and a value of `6, 21` is to complete the writing process.  There also appears to be a request of `7, 0` and `7, 1`, but I am unsure of its use, and it does not appear to be necessary. After this is followed by a two byte little endian value indicating the amount of data to send or receive, a two byte value left as zero for the Pro2 (6003) model, a four byte little endian value for the total size of the data, and a four byte little endian value for the offset of the current request.

It is important that whatever method is used to write the packet to the HID file does so in a single write operation;  if the packet ends up split into two or more write operations, each write operation will be interpreted as separate packats, rather than the separate write operations being interpreted as a proper 64 byte packet.  If attempting to combine the output of separate commands into a single request packet, having the data processed using `dd iflags=fullblock` will be necessary so that the separate writes from the separate commands are properly sent as a single write operation.

## Response packet format
All responses from the Pro2 controller consist of an 18 byte header and up to 46 bytes of data.  The first four bytes are made up of three values, the first byte being `2`, which coincides with the output endpoint address, the second byte being `4`, and the remaining two bytes being `4` little endian encoded.  I assume one (if not both) of those `4` values correspondes to the `4` used in the request, which appear to correspond to configuration requests.  The next two bytes are the little endian encoded request type, `1` for writing config data, `2` for reading config data, and `6` for completing the write request.  The next four bytes are litte endian encoded size of data sent or received.  It appears for some Ultimate devices that the controller may not properly have the high word set to zero, as there appears to be code which zero out the high word on these devices when reading the data.  The next four bytes are little endian encoded total data size, and the final four bytes are little endian encoded offset of the current operation.

## Get current slot
The current slot number is part of the configuration data, a two byte value offset 18 bytes.  As a shortcut to not have to load the entire configuration, this value can be obtained by reading just the first 20 bytes, then obtaining the last two bytes.

## Read configuration
The read configuration request command has a value of `2, 0`, the size of the configuration is 1652 bytes, and the maximum allowable data packet buffer size between read and write configuration is 45 bytes.  The typical request and response packet for reading configuration data is represented below, representing the low and high byte of the 2 byte offset values as OL and OH, repsectively.
```
Request (36x loop):
81 3E 04
02 00 00 00
2D 00 00 00
74 06 00 00
OL OH 00 00
arbitrary ignored data (45 bytes)

Response (36x loop):
02 04 04 00
02 00
2D 00 00 00
74 06 00 00
OL OH 00 00
data (45 bytes)

Final request:
81 3E 04
02 00 00 00
20 00 00 00
74 06 00 00
54 06 00 00
arbitrary ignored data (45 bytes)

Final response:
02 04 04 00
02 00
20 00 00 00
74 06 00 00
54 06 00 00
data (32 bytes)
```
The script <diReadPro2.sh> will repeatedly read portions of the configuration data, then rebuild the configuration data as a 1652 byte binary file.  The first parameter should be the `hidraw` file, and the second parameter should be the filename which will contain the binary configuration data.

## CRC 16
After analyzing the results using the CRC16 function present in 8BitDoAdvance.dll using a small set of fabricated configuration binary data, and comparing the result to various CRC16 algorithms of the provided binary data, the results appear to match an implementation titled `CRC-16/MCRF4XX`, with the exception that the high byte is swapped with the low byte.  Given that this value is written to the binary data as little endian, this effectively translates as being bid endian encoded in the binary data.  However, it appears that this value is calculated by the Ultimate Software multiple times, each time with the previous CRC16 value present in the binary data, and the new CRC16 value overwriting the previous value, thus it can not effectively be used to validate the data, as some of the data needed to recalculate the CRC16 for validation will be missing.

## Write configuration
The write configuration request command has a value of 1, the total size of the configuration data is 1652 bytes, and the largest allowable data buffer that can be used for both request and response packets is 45 bytes.  The typical request and response packet for writing configuration data is represented below, representing the low and high byte of the 2 byte offset values as OL and OH, repsectively.
```
Request (36x loop):
81 3E 04
01 00 00 00
2D 00 00 00
74 06 00 00
OL OH 00 00
data (45 bytes)

Response (36x loop):
02 04 04 00
01 00
2D 00 00 00
74 06 00 00
OL OH 00 00
arbitrary data, should be ignored (46 bytes)

Final request:
81 3E 04
01 00 00 00
20 00 00 00
74 06 00 00
54 06 00 00
data (32 bytes)
arbitrary ignored data (13 bytes)

Final response:
02 04 04 00
01 00
20 00 00 00
74 06 00 00
54 06 00 00
arbitrary data, should be ignored (46 bytes)
```


Once the complete configuration data has been properly written to the device, a final request must be sent to the device to commit the configuration data.  This has a request type of `6, 21`, and has no data associated with it.  Given there is no data, the packet size will remain with a value of `17`, corresponding to the packet header size, and the packet data size, full data size, and offset will remain zero.  The response will echo `6` as the request type, and will also have zero for the packet data size, complete data size, and offset.  The data section of the request packet will be ignored by the device, and the data section of the response will be arbitrary, and should be ignored.

```
Request:
81 11 04
06 00 15 00
00 00 00 00
00 00 00 00
00 00 00 00
data (45 bytes)

Response:
02 04 04 00
06 00
00 00 00 00
00 00 00 00
00 00 00 00
arbitrary data, should be ignored (46 bytes)
```

The provided <diWritePro2.sh> script will write a properly formatted binary configuration file to the device.  The first parameter must be to the correct `hidraw` file, and the second parameter must be to the file containing the configuration data.

# Configuration Binary Format
WIP