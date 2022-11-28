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

# Configuration Binary Format WIP

The configuration binary format is a 1652 byte record containing information
on how to configure each of the three profiles available on the controller.
The configuration is devided into eight sections, each section not including
the header section containing configuration for all three profiles.

## Enable flags
The header, as well as each profile division within the other sections, contains
a four byte enable flag.  A value of `0x20190911`, little endian encoded, indicates
the profile is enabled.  It appears that a value of `0` is used to indicate the
profile has not yet been enabled.  Also, analysis of the Ultimate Software
program appears to indicate that a value of `0x20190000`, little endian encoded,
is supposed to indicate the profile is disabled, but it does not appear to be
used.

## Header (20 bytes)
The header contains three enable flags for the entirety of three profiles
in order.  This is followed by a four byte section for the CRC 16, byte swapped,
zero extended to 32 bytes, little endian encoded, making for a mixed
endian encoding.  Afterwards is a two byte value indicating gamepad mode, little
endian encoded which can either be 0 for Switch, 1 for DInput, 2 for Mac, and 3
for XInput.  As far as I can tell, the Ultimate Software does not allow
configuration in Mac mode.  There also appears to be a possible value of 4, but
remains unused.  The remaining two byte value is little endian encoded value
indicating current profile.  As far as I can tell, this value is only used so
the Ultimate Software can keep track of which profile was most recently selected
so the next session can resume with the profile most recently edited from the
previous session.

|Offset|Size|Description            |
|------|----|-----------------------|
|  0x00|   4| Profile 1 Enable Flag |
|  0x04|   4| Profile 2 Enable Flag |
|  0x08|   4| Profile 3 Enable Flag |
|  0x0C|   4| CRC16 value           |
|  0x10|   2| Gamepad Mode          |
|  0x12|   2| Current slot          |


## Filenames (96 bytes)
The filename section contains the filenames associated with each profile in order.
Each filename is 32 bytes.  From what I can tell, the software itself only
assigns one of two different values.  A minimum (0) value is assigned to each
byte for a profile which has not been modified (and will not be selectable),
and a maximum (255) value is assigned to each byte for a profile which has
been modified.  While I have not yet figured out how to test this, analysis of
the Ultimate Software suggests that the filenames for the profiles can come
from ini configuration files if the configuration file is not using a default
filename.

|Offset|Size|Description         |
|------|----|--------------------|
|  0x14|  32| Profile 1 Filename |
|  0x34|  32| Profile 2 Filename |
|  0x54|  32| Profile 3 Filename |


## Rumble (36 bytes)
The rumble section contains the rumble motor string configuration for each
profile.  The first four bytes is the enable flag, the next four bytes is
the strength of the left motor, and the final four bytes is the strength
of the right motor.  The strength is a four byte floating point number
between 0 (motor off) and 1 (motor full strenght).  The Ultimate Software
will assign a value of 0, 0.2, 0.4, 0.6, 0.8, or 1.

|Offset|Size|Description                     |
|------|----|--------------------------------|
|  0x74|   4| Profile 1 Rumble Enable Flag   |
|  0x78|   4| Profile 1 Left Motor Strength  |
|  0x7C|   4| Profile 1 Right Motor Strength |
|  0x80|   4| Profile 2 Rumble Enable Flag   |
|  0x84|   4| Profile 2 Left Motor Strength  |
|  0x88|   4| Profile 2 Right Motor Strength |
|  0x8C|   4| Profile 3 Rumble Enable Flag   |
|  0x90|   4| Profile 3 Left Motor Strength  |
|  0x94|   4| Profile 3 Right Motor Strength |


## Joystick (24 bytes)
The joystick section contains deadzone configuration for the joysticks indicating
how far a stick must be tilted before the gamepad reports the stick is tilted, and
how far the stick can be tilted before the gamepad reports the stick is titled as
far as it can be.  It appears the values range from 0 (the stick in perfect neutral
position) and 128 (the stick pushed against the edge).  The default value for the
start position is 0, and the default value for the end position is 128.  Assigning
a value larger than 0 to the start value prevents a loose neutral position from
sending tilt data, and assigning the end position a value less than 128 allows
the gamepad to report 100% tilt without having to press the stick agains the edge.
The first four bytes is the joystick enable flag, the next four bytes in order are
the left stick start value, the left stick end value, the right stick start value,
and the right stick end value.  This is repeated for each profile.

|Offset|Size|Description                        |
|------|----|-----------------------------------|
|  0x98|   4| Profile 1 Joystick Enable Flag    |
|  0x9C|   1| Profile 1 Left Stick Start Value  |
|  0x9D|   1| Profile 1 Left Stick End Value    |
|  0x9E|   1| Profile 1 Right Stick Start Value |
|  0x9F|   1| Profile 1 Right Stick End Value   |
|  0xA0|   4| Profile 2 Joystick Enable Flag    |
|  0xA4|   1| Profile 2 Left Stick Start Value  |
|  0xA5|   1| Profile 2 Left Stick End Value    |
|  0xA6|   1| Profile 2 Right Stick Start Value |
|  0xA7|   1| Profile 2 Right Stick End Value   |
|  0xA8|   4| Profile 3 Joystick Enable Flag    |
|  0xAC|   1| Profile 3 Left Stick Start Value  |
|  0xAD|   1| Profile 3 Left Stick End Value    |
|  0xAE|   1| Profile 3 Right Stick Start Value |
|  0xAF|   1| Profile 3 Right Stick End Value   |

## Trigger (24 bytes)
The trigger section is similar to the joystick section, indicating how far
the triggers must be pulled before the gamepad reports they have been
pulled, and how far the triggers can be pulled before the gamepad reports
they have been pulled completely.  These values range from 0 being the
neutral postion, and 255 being pulled completely.  The default values for
the start positions are 77, and the default values for the end positions
are 255.  The values are encoded identially to the Joystick section.

|Offset|Size|Description                          |
|------|----|-------------------------------------|
|  0xB0|   4| Profile 1 Trigger Enable Flag       |
|  0xB4|   1| Profile 1 Left Trigger Start Value  |
|  0xB5|   1| Profile 1 Left Trigger End Value    |
|  0xB6|   1| Profile 1 Right Trigger Start Value |
|  0xB7|   1| Profile 1 Right Trigger End Value   |
|  0xB8|   4| Profile 2 Trigger Enable Flag       |
|  0xBC|   1| Profile 2 Left Trigger Start Value  |
|  0xBD|   1| Profile 2 Left Trigger End Value    |
|  0xBE|   1| Profile 2 Right Trigger Start Value |
|  0xBF|   1| Profile 2 Right Trigger End Value   |
|  0xC0|   4| Profile 3 Trigger Enable Flag       |
|  0xC4|   1| Profile 3 Left Trigger Start Value  |
|  0xC5|   1| Profile 3 Left Trigger End Value    |
|  0xC6|   1| Profile 3 Right Trigger Start Value |
|  0xC7|   1| Profile 3 Right Trigger End Value   |


## Special Features (24 bytes) WIP
The special features section encodes various additional options, such
as swapping sticks, swapping triggers, swapping axis, etc.  The first
four byte value is the enable flag, and t remaining four byte value is
a 32 bit set of selected options.  This is repeated for each profile.


| Bit | Function                       |
|-----|--------------------------------|
|   0 | Swap left stick X axis         |
|   1 | Swap left stick Y axis         |
|   2 | Swap right stick X axis        |
|   3 | Swap right stick Y axis        |
|   4 | Swap left and right sticks     |
|   5 | Unused                         |
|   6 | Unused                         |
|   7 | Swap left and right triggers   |
|   8 | Swap left stick and D-Pad      |
|   9 | Unknown                        |
|  10 | Swap right stick and triggers  |
|  11 | Rumble high motion sensitivity |
|  12 | Unknown                        |
|  13 | Unused                         |
|  14 | Unused                         |
|  15 | Unused                         |
|  16 | Unused                         |
|  17 | Unused                         |
|  18 | Unused                         |
|  19 | Unused                         |
|  20 | Unused                         |
|  21 | Unused                         |
|  22 | Unused                         |
|  23 | Unused                         |
|  24 | Unused                         |
|  25 | Unused                         |
|  26 | Unused                         |
|  27 | Unused                         |
|  28 | Unused                         |
|  29 | Unused                         |
|  30 | Unused                         |
|  31 | Unused                         |

While there does appear to be functionality associated with bit 9 and bit 12, I was unable
to find any user interface options within the Ultimate Software which actually set the bits.

|Offset|Size|Description                            |
|------|----|---------------------------------------|
|  0xC8|   4| Profile 1 Special Feature Enable Flag |
|  0xCC|   4| Profile 1 Special Feature Bit Set     |
|  0xD0|   4| Profile 1 Special Feature Enable Flag |
|  0xD4|   4| Profile 1 Special Feature Bit Set     |
|  0xD8|   4| Profile 1 Special Feature Enable Flag |
|  0xDC|   4| Profile 1 Special Feature Bit Set     |


## Button mapping (252 bytes) WIP
The button mapping sections assigns functions to physical button presses.
A function can either be a button, a macro, or a built in process such
as enabling turbo mode or dynamic button swapping.  The first four byte
value is the enable flag.  The next 20 four byte values are the little
endian encoded function values, each corresponding to a physical button
press.  Each function value is encoded as a bit set with only one bit set.
This is repeated for each profile.

In order, the physical buttons for each function value is A, B, X, Y, L,
R, L2, R2, L3, R3, Select, Start, Share, Home, Up, Down, Left, Right, P1,
and P2.  The following table lists the functions with their corresponding
values.
| Bit   | Function            |
|-------|---------------------|
| Empty | Button is disabled  |
|     0 | Start button        |
|     1 | L3                  | 
|     2 | R3                  |
|     3 | Select              |
|     4 | X                   |
|     5 | Y                   |
|     6 | Right               |
|     7 | Left                |
|     8 | Down                |
|     9 | Up                  |
|    10 | L1                  |
|    11 | R1                  |
|    12 | B                   |
|    13 | A                   |
|    14 | L2                  |
|    15 | Home                |
|    16 | Menu                |
|    17 | R2                  |
|    18 | Bluetooth Connect   |
|    19 | Unknown             |
|    20 | Unknown             |
|    21 | Unknown             |
|    22 | Screenshot          |
|    23 | Turbo Single        |
|    24 | Turbo Auto          |
|    25 | P1                  |
|    26 | P2                  |
|    27 | Dynamic button swap |
|    28 | Unknwon             |
|    29 | Unknown             |
|    30 | Unknown             |
|    31 | Unknown             |

Given that the four most significant bits are currently unknown, it seems
likely that they may correspond to the four available custom macros to assign.

|Offset|Size|Description                           |
|------|----|--------------------------------------|
| 0x0E0|   4| Profile 1 Button Mapping Enable Flag |
| 0x0E4|   4| Profile 1 Button A Function          |
| 0x0E8|   4| Profile 1 Button B Function          |
| 0x0EC|   4| Profile 1 Button X Function          |
| 0x0F0|   4| Profile 1 Button Y Function          |
| 0x0F4|   4| Profile 1 Button L Function          |
| 0x0F8|   4| Profile 1 Button R Function          |
| 0x0FC|   4| Profile 1 Button L2 Function         |
| 0x100|   4| Profile 1 Button R2 Function         |
| 0x104|   4| Profile 1 Button L3 Function         |
| 0x108|   4| Profile 1 Button R3 Function         |
| 0x10C|   4| Profile 1 Button Select Function     |
| 0x110|   4| Profile 1 Button Start Function      |
| 0x114|   4| Profile 1 Button Share Function      |
| 0x118|   4| Profile 1 Button Home Function       |
| 0x11C|   4| Profile 1 Button Up Function         |
| 0x120|   4| Profile 1 Button Down Function       |
| 0x124|   4| Profile 1 Button Left Function       |
| 0x128|   4| Profile 1 Button Right Function      |
| 0x12C|   4| Profile 1 Button P1 Function         |
| 0x130|   4| Profile 1 Button P2 Function         |
| 0x134|   4| Profile 2 Button Mapping Enable Flag |
| 0x138|   4| Profile 2 Button A Function          |
| 0x13C|   4| Profile 2 Button B Function          |
| 0x140|   4| Profile 2 Button X Function          |
| 0x144|   4| Profile 2 Button Y Function          |
| 0x148|   4| Profile 2 Button L Function          |
| 0x14C|   4| Profile 2 Button R Function          |
| 0x150|   4| Profile 2 Button L2 Function         |
| 0x154|   4| Profile 2 Button R2 Function         |
| 0x158|   4| Profile 2 Button L3 Function         |
| 0x15C|   4| Profile 2 Button R3 Function         |
| 0x160|   4| Profile 2 Button Select Function     |
| 0x164|   4| Profile 2 Button Start Function      |
| 0x168|   4| Profile 2 Button Share Function      |
| 0x16C|   4| Profile 2 Button Home Function       |
| 0x170|   4| Profile 2 Button Up Function         |
| 0x174|   4| Profile 2 Button Down Function       |
| 0x178|   4| Profile 2 Button Left Function       |
| 0x17C|   4| Profile 2 Button Right Function      |
| 0x180|   4| Profile 2 Button P1 Function         |
| 0x184|   4| Profile 2 Button P2 Function         |
| 0x188|   4| Profile 3 Button Mapping Enable Flag |
| 0x18C|   4| Profile 3 Button A Function          |
| 0x190|   4| Profile 3 Button B Function          |
| 0x194|   4| Profile 3 Button X Function          |
| 0x198|   4| Profile 3 Button Y Function          |
| 0x19C|   4| Profile 3 Button L Function          |
| 0x1A0|   4| Profile 3 Button R Function          |
| 0x1A4|   4| Profile 3 Button L2 Function         |
| 0x1A8|   4| Profile 3 Button R2 Function         |
| 0x1AC|   4| Profile 3 Button L3 Function         |
| 0x1B0|   4| Profile 3 Button R3 Function         |
| 0x1B4|   4| Profile 3 Button Select Function     |
| 0x1B8|   4| Profile 3 Button Start Function      |
| 0x1BC|   4| Profile 3 Button Share Function      |
| 0x1C0|   4| Profile 3 Button Home Function       |
| 0x1C4|   4| Profile 3 Button Up Function         |
| 0x1C8|   4| Profile 3 Button Down Function       |
| 0x1CC|   4| Profile 3 Button Left Function       |
| 0x1D0|   4| Profile 3 Button Right Function      |
| 0x1D4|   4| Profile 3 Button P1 Function         |
| 0x1D8|   4| Profile 3 Button P2 Function         |


## Macros (1176 bytes) WIP
The macro section defines custom macros for the controller.  Each profile
can have up to four macros defined.  Each macro contains a key map, which
might correspond to a function value which can be assigned to a button
mapping, and up to 18 macro steps, each step consisting a number of button
presses, 8 directional joystick presses, and a delay before processing the
next step.  While I have not fully analyzed exactly how macros work yet,
I have included them in the byte map, with the `c` after the enable flag
indicating the total count of macros, the key map value abbreviated `km`,
the time interval array abbreviated `t`, the buttons abbreviated `k`, the
8 directional joystick data as `digital joystic data`, and the `c` after
the 8 directional joystick data indicating the total count of steps in
the macro.  In configuration data that I have dumped from my controller
which have no macros defined, the enable flags are set to the enable
value, while all other bytes are set to zero.  I assume it is also
possible to have the entire macro section as zero if macros are not desired.


## Complete byte map of configuration
Listed below is a complete byte map of the configuration data, written 32
bytes per line.  This table can be used to assist editing the configuration
data directly in a hex editor which allows displaying 32 bytes per column.
All cells marked with `-` are padding bytes to align the data structure,
and should probably be set to `0`.

```
       0                               1
       0 1 2 3 4 5 6 7 8 9 A B C D E F 0 1 2 3 4 5 6 7 8 9 A B D C E F
0x00| | flag1 | flag2 | flag3 |  crc  | m | s | filename1
0x02|  ->                                     | filename2
0x04|  ->                                     | filename3
0x06|  ->                                     | r1flg | r1v1  | r1v2  |
0x08| | r2flg | r2v1  | r2v2  | r3flg | r3v1  | r3v2  | j1flg |s|e|s|e|
0x0A| | j2flg |s|e|s|e| j3flg |s|e|s|e| t1flg |s|e|s|e| t2flg |s|e|s|e| 
0x0C| | t3flg |s|e|s|e| f1flg | f1val | f2flg | f2val | f3flg | f3val | 
0x0E| | m1flg |   A   |   B   |   X   |   Y   |   L   |   R   |  L2   |
0x10| |  R2   |  L3   |  R3   |Select | Start | Share | Home  |  Up   |
0x12| | Down  | Left  | Right |  P1   |  P2   | m2flg |   A   |   B   |
0x14| |   X   |   Y   |   L   |   R   |  L2   |  R2   |  L3   |  R3   |
0x16| |Select | Start | Share | Home  |  Up   | Down  | Left  | Right |
0x18| |  P1   |  P2   | m3flg |   A   |   B   |   X   |   Y   |   L   |
0x1A| |   R   |  L2   |  R2   |  L3   |  R3   |Select | Start | Share |
0x1C| | Home  |  Up   | Down  | Left  | Right |  P1   |  P2   |mcr1flg|
0x1E| |c|  -  |mcr1km1|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|
0x20| |t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|
0x22| |k11|k12|k13|k14|k15|k16|k17|k18|  macro1-1 digital joystick data
0x24| ->  |i|-|mcr1km2|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|
0x26| |t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|
0x28| |k11|k12|k13|k14|k15|k16|k17|k18|  macro1-2 digital joystick data
0x2A| ->  |i|-|mcr1km3|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|
0x2C| |t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|
0x2E| |k11|k12|k13|k14|k15|k16|k17|k18|  macro1-3 digital joystick data
0x30| ->  |i|-|mcr1km4|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|
0x32| |t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|
0x34| |k11|k12|k13|k14|k15|k16|k17|k18|  macro1-4 digital joystick data
0x36| ->  |i|-|mcr2flg|c|  -  |mcr2km1|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |
0x38| |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |
0x3A| |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|  macro2-1
0x3C| -> joystick data    |c|-|mcr2km2|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |
0x3E| |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |
0x40| |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|  macro2-2
0x42| -> joystick data    |c|-|mcr2km3|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |
0x44| |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |
0x46| |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|  macro2-3
0x48| -> joystick data    |c|-|mcr2km4|t1 |t2 |t3 |t4 |t5 |t6 |t7 |t8 |
0x4A| |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |k3 |k4 |k5 |k6 |
0x4C| |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|  macro2-4
0x4E| -> joystick data    |c|-|mcr3flg|c|  -  |mcr3km1|t1 |t2 |t3 |t4 |
0x50| |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |
0x52| |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|
0x54| |  macro3-1 digital joystick data   |c|-|mcr3km2|t1 |t2 |t3 |t4 |
0x56| |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |
0x58| |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|
0x5A| |  macro3-2 digital joystick data   |c|-|mcr3km3|t1 |t2 |t3 |t4 |
0x5C| |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |
0x5E| |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|
0x60| |  macro3-3 digital joystick data   |c|-|mcr3km4|t1 |t2 |t3 |t4 |
0x62| |t5 |t6 |t7 |t8 |t9 |t10|t11|t12|t13|t14|t15|t16|t17|t18|k1 |k2 |
0x64| |k3 |k4 |k5 |k6 |k7 |k8 |k9 |k10|k11|k12|k13|k14|k15|k16|k17|k18|
0x66| |  macro3-4 digital joystick data   |c|-|
```