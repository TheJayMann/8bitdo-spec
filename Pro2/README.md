# 8bitdo Pro2
Based on analysis of the 8BitDoAdvance.dll export table, a read, write, current slot, and CRC function are shared with Pro2, Ultimate2_4, UltimateBT, and Ultimate_PC.  This would indicate that all of these devices are treated the same, and share an identical protocol.  However, further analysis of these individual functions indicate that specific PID values have slight variations in the protocol.  The only device I have to test with this is an older Pro2 model (PID 0x6003), which does not have any variations to the protocol.  This folder will document my findings with this specific model of controller.

## Request packet format
All requests made to the Pro2 controller consist of a three byte header, a 16 byte request, and up to 45 bytes of data.

The three byte header starts first with the hex value `81`, which, according to HID documentation, should represent the report number being used.  I have not been able to read the report descriptors for the device, and cannot determine if this is an actual report number or not.  This does happen to match the input endpoint address, though perhaps coincidentally. The second byte of the header appears to be the size of the buffer to be used to read the response data.  Given that the device specifies a packet size of 64, this should be equal to or less than this value.  The third byte has a value of `4` when operating on configuration data.  Given that the response buffer size is typically (perhaps always) 63, the header will typically contain `81 3E 04`.

For the request, the first four bytes appear to be a two byte request type, followed by a two byte subrequest type, or possibly a request parameter, in little endian.  The value of `1, 0` is to write config data, a value of `2, 0` is to read config data, and a value of `6, 21` is to complete the writing process.  There also appears to be a request of `7, 0` and `7, 1`, but I am unsure of its use, and it does not appear to be necessary. After this is followed by a two byte little endian value indicating the amount of data to send or receive, a two byte value little endian encoded checksum, a four byte little endian value for the total size of the data, and a four byte little endian value for the offset of the current request.  For the checksum value, this is the CRC-16/MODBUS of the data to be sent (with a hex value of `FFFF` if no data is present) for devices with PID value of 3010, 3011, 3109, 6006, and 6007.  For all other devices using the Pro2 protocol, the checksum value of `0` is used.

It is important that whatever method is used to write the packet to the HID file does so in a single write operation;  if the packet ends up split into two or more write operations, each write operation will be interpreted as separate packats, rather than the separate write operations being interpreted as a proper 64 byte packet.  If attempting to combine the output of separate commands into a single request packet, having the data processed using `dd iflags=fullblock` will be necessary so that the separate writes from the separate commands are properly sent as a single write operation.

## Response packet format
All responses from the Pro2 controller consist of an 18 byte header and up to 46 bytes of data.  The first four bytes are made up of three values, the first byte being `2`, which coincides with the output endpoint address, the second byte being `4`, and the remaining two bytes being `4` little endian encoded.  I assume one (if not both) of those `4` values correspondes to the `4` used in the request, which appear to correspond to configuration requests.  The next two bytes are the little endian encoded request type, `1` for writing config data, `2` for reading config data, and `6` for completing the write request.  The next four bytes are litte endian encoded size of data sent or received.  For devices with PID 3010, 3011, 3109, 6006, and 6007, the high word is set to zero in 8BitDoAdvance.dll.  Given that this device list coincides with the device list which calculates a checksum for the request packet, it is likely that these devices are also sending a checksum of the response data, and the code is clearing it so the checksum does not interfere with memory copy operations.  The next four bytes are little endian encoded total data size, and the final four bytes are little endian encoded offset of the current operation.

## Get current slot
The current slot number is part of the configuration data, a two byte value offset 18 bytes.  As a shortcut to not have to load the entire configuration, this value can be obtained by reading just the first 20 bytes, then obtaining the last two bytes.

## Read configuration
The read configuration request command has a value of `2, 0`, the size of the configuration is 1652 bytes, and the maximum allowable data packet buffer size between read and write configuration is 45 bytes.  The typical request and response packet for reading configuration data is represented below, representing checksum values as XX, and the low and high byte of the 2 byte offset values as OL and OH, repsectively.
```
Request (36x loop):
81 3E 04
02 00 00 00
2D 00 XX XX
74 06 00 00
OL OH 00 00
arbitrary ignored data (45 bytes)

Response (36x loop):
02 04 04 00
02 00
2D 00 XX XX
74 06 00 00
OL OH 00 00
data (45 bytes)

Final request:
81 3E 04
02 00 00 00
20 00 XX XX
74 06 00 00
54 06 00 00
arbitrary ignored data (45 bytes)

Final response:
02 04 04 00
02 00
20 00 XX XX
74 06 00 00
54 06 00 00
data (32 bytes)
```
The script <diReadPro2.sh> will repeatedly read portions of the configuration data, then rebuild the configuration data as a 1652 byte binary file.  The first parameter should be the `hidraw` file, and the second parameter should be the filename which will contain the binary configuration data.  This script was designed for the older Pro2 controller (PID 6003), and assumes all checksum values in requests and responses are all `0`.

## CRC 16
After analyzing the results using the CRC16 function present in 8BitDoAdvance.dll using a small set of fabricated configuration binary data, and comparing the result to various CRC16 algorithms of the provided binary data, the results appear to match an implementation titled `CRC-16/MCRF4XX`, with the exception that the high byte is swapped with the low byte.  Given that this value is written to the binary data as little endian, this effectively translates as being bid endian encoded in the binary data.  However, it appears that this value is calculated by the Ultimate Software multiple times, each time with the previous CRC16 value present in the binary data, and the new CRC16 value overwriting the previous value, thus it can not effectively be used to validate the data, as some of the data needed to recalculate the CRC16 for validation will be missing.

## Write configuration
The write configuration request command has a value of 1, the total size of the configuration data is 1652 bytes, and the largest allowable data buffer that can be used for both request and response packets is 45 bytes.  The typical request and response packet for writing configuration data is represented below, representing checksum values as XX, and the low and high byte of the 2 byte offset values as OL and OH, repsectively.
```
Request (36x loop):
81 3E 04
01 00 00 00
2D 00 XX XX
74 06 00 00
OL OH 00 00
data (45 bytes)

Response (36x loop):
02 04 04 00
01 00
2D 00 XX XX
74 06 00 00
OL OH 00 00
arbitrary data, should be ignored (46 bytes)

Final request:
81 3E 04
01 00 00 00
20 00 XX XX
74 06 00 00
54 06 00 00
data (32 bytes)
arbitrary ignored data (13 bytes)

Final response:
02 04 04 00
01 00
20 00 XX XX
74 06 00 00
54 06 00 00
arbitrary data, should be ignored (46 bytes)
```


Once the complete configuration data has been properly written to the device, a final request must be sent to the device to commit the configuration data.  This has a request type of `6, 21`, and has no data associated with it.  Given there is no data, the packet size will remain with a value of `17`, corresponding to the packet header size, and the packet data size, full data size, and offset will remain zero.  The response will echo `6` as the request type, and will also have zero for the packet data size, complete data size, and offset.  The data section of the request packet will be ignored by the device, and the data section of the response will be arbitrary, and should be ignored.

```
Request:
81 11 04
06 00 15 00
00 00 XX XX
00 00 00 00
00 00 00 00
data (45 bytes)

Response:
02 04 04 00
06 00
00 00 XX XX
00 00 00 00
00 00 00 00
arbitrary data, should be ignored (46 bytes)
```

The provided <diWritePro2.sh> script will write a properly formatted binary configuration file to the device.  The first parameter must be to the correct `hidraw` file, and the second parameter must be to the file containing the configuration data.  This script was designed for the older Pro2 controller (PID 6003), and assumes all checksum values in requests and responses are all `0`.

# Configuration Binary Format

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

Attempting to set these values directly and examining the results in the Ultimate
Software shows that these filenames are displayed as custom names for the profile,
and are encoded as UTF16LE, allowing each profile to have up to a 16 character
custom name.

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


## Special Features (24 bytes)
The special features section encodes various additional options, such
as swapping sticks, swapping triggers, swapping axis, etc.  The first
four byte value is the enable flag, and the remaining four byte value
is a 32 bit set of selected options.  This is repeated for each profile.


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


## Button mapping (252 bytes)
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


## Macros (1176 bytes)
The macro section defines custom macros for the controller.  Each profile
can have up to four macros defined.  Each macro is assigned to a button,
and can contains up to 18 entries. Each entry defines a button input set,
a joystick input set, and a hold interval.  For each profile, the first
four byte value is the enable flag.  The next single byte value is the
total count of macros defined for the profile. The next three bytes are
used for data alignment and otherwise ignored.  At this point, the first
macro definition begins.  The first four byte value here is the button
assigned to the macro.  The value assigned can be found in the button
mapping table listed above.  If the button assigned to the macro is also
assigned via button mapping, the macro will override the button mapping.
The next 18 two byte values are the little end encoded intervals in
millisecons that the button and joystick data will be held before
performing the next entry in the macro, or ending the macro, assuming
the entry is the last in the macro.  A default value of 31 milliseconds
is assigned by the Ultimate Software if no time interval is specified
for an entry.  The next 18 two byte values are the little endian encoded
button mappings for each entry.  The following 18 one byte values are the
digital joystick values for each entry.  The next byte is a count of the
number of entries in the macro.  The next byte is used for padding and
otherwise unused.  This macro definition is then repeated three more times
to define all four macros for the profile.  This entire profile macro data
is then repeated two more times to define all three profile macro data.

### Button Bit Set
The button input bit set used for macros appear to match the low word bits used
for button mapping, with the exception that Start and Select buttons do not
appear in the macro editor, and the corresponding bits do not appear to be able
to be set using the Ultimate Software,and bit 15 is mapped to R2 rather than
Home.  Also to note is that there is a function in the Ultimate Software which
swaps the bit for Home and R2 (bits 15 and 17) and back again; it is possible 
that it does it for this reason.  It is possible that setting bits 0 and 3 may
allow macros which send Start and Select button presses, but this remains
untested for now.
| Bit   | Button input                    |
|-------|---------------------------------|
| Empty | No button input                 |
|     0 | Unused (possibly Start button)  |
|     1 | L3                              |
|     2 | R3                              |
|     3 | Unused (possibly Select button) |
|     4 | X                               |
|     5 | Y                               |
|     6 | Right                           |
|     7 | Left                            |
|     8 | Down                            |
|     9 | Up                              |
|    10 | L1                              |
|    11 | R1                              |
|    12 | B                               |
|    13 | A                               |
|    14 | L2                              |
|    15 | R2                              |

### Digital Joystick Bit Set
Joystick values set as macro entries are represented as full tilt combinations of
up, down, left, and right for the left and right joysticks.
| Bit   | Joystick input      |
|-------|---------------------|
| Empty | No joystick input   |
|     0 | Left stick up       |
|     1 | Left stick down     |
|     2 | Left stick left     |
|     3 | Left stick right    |
|     4 | Right stick up      |
|     5 | Right stick down    |
|     6 | Right stick left    |
|     7 | Right stick right   |


|Offset|Size|Description                                        |
|------|----|---------------------------------------------------|
| 0x1DC|   4| Profile 1 Macro Enable Flag                       |
| 0x1E0|   1| Profile 1 Macro Total Count                       |
| 0x1E4|   4| Profile 1 Macro 1 Button Assignment               |
| 0x1E8|   2| Profile 1 Macro 1 Entry 1 Hold Interval           |
| 0x1EA|   2| Profile 1 Macro 1 Entry 2 Hold Interval           |
| 0x1EC|   2| Profile 1 Macro 1 Entry 3 Hold Interval           |
| 0x1EE|   2| Profile 1 Macro 1 Entry 4 Hold Interval           |
| 0x1F0|   2| Profile 1 Macro 1 Entry 5 Hold Interval           |
| 0x1F2|   2| Profile 1 Macro 1 Entry 6 Hold Interval           |
| 0x1F4|   2| Profile 1 Macro 1 Entry 7 Hold Interval           |
| 0x1F6|   2| Profile 1 Macro 1 Entry 8 Hold Interval           |
| 0x1F8|   2| Profile 1 Macro 1 Entry 9 Hold Interval           |
| 0x1FA|   2| Profile 1 Macro 1 Entry 10 Hold Interval          |
| 0x1FC|   2| Profile 1 Macro 1 Entry 11 Hold Interval          |
| 0x1FE|   2| Profile 1 Macro 1 Entry 12 Hold Interval          |
| 0x200|   2| Profile 1 Macro 1 Entry 13 Hold Interval          |
| 0x202|   2| Profile 1 Macro 1 Entry 14 Hold Interval          |
| 0x204|   2| Profile 1 Macro 1 Entry 15 Hold Interval          |
| 0x206|   2| Profile 1 Macro 1 Entry 16 Hold Interval          |
| 0x208|   2| Profile 1 Macro 1 Entry 17 Hold Interval          |
| 0x20A|   2| Profile 1 Macro 1 Entry 18 Hold Interval          |
| 0x20C|   2| Profile 1 Macro 1 Entry 1 Button Input            |
| 0x20E|   2| Profile 1 Macro 1 Entry 2 Button Input            |
| 0x210|   2| Profile 1 Macro 1 Entry 3 Button Input            |
| 0x212|   2| Profile 1 Macro 1 Entry 4 Button Input            |
| 0x214|   2| Profile 1 Macro 1 Entry 5 Button Input            |
| 0x216|   2| Profile 1 Macro 1 Entry 6 Button Input            |
| 0x218|   2| Profile 1 Macro 1 Entry 7 Button Input            |
| 0x21A|   2| Profile 1 Macro 1 Entry 8 Button Input            |
| 0x21C|   2| Profile 1 Macro 1 Entry 9 Button Input            |
| 0x21E|   2| Profile 1 Macro 1 Entry 10 Button Input           |
| 0x220|   2| Profile 1 Macro 1 Entry 11 Button Input           |
| 0x222|   2| Profile 1 Macro 1 Entry 12 Button Input           |
| 0x224|   2| Profile 1 Macro 1 Entry 13 Button Input           |
| 0x226|   2| Profile 1 Macro 1 Entry 14 Button Input           |
| 0x228|   2| Profile 1 Macro 1 Entry 15 Button Input           |
| 0x22A|   2| Profile 1 Macro 1 Entry 16 Button Input           |
| 0x22C|   2| Profile 1 Macro 1 Entry 17 Button Input           |
| 0x22E|   2| Profile 1 Macro 1 Entry 18 Button Input           |
| 0x230|   1| Profile 1 Macro 1 Entry 1 Digital Joystick Input  |
| 0x231|   1| Profile 1 Macro 1 Entry 2 Digital Joystick Input  |
| 0x232|   1| Profile 1 Macro 1 Entry 3 Digital Joystick Input  |
| 0x233|   1| Profile 1 Macro 1 Entry 4 Digital Joystick Input  |
| 0x234|   1| Profile 1 Macro 1 Entry 5 Digital Joystick Input  |
| 0x235|   1| Profile 1 Macro 1 Entry 6 Digital Joystick Input  |
| 0x236|   1| Profile 1 Macro 1 Entry 7 Digital Joystick Input  |
| 0x237|   1| Profile 1 Macro 1 Entry 8 Digital Joystick Input  |
| 0x238|   1| Profile 1 Macro 1 Entry 9 Digital Joystick Input  |
| 0x239|   1| Profile 1 Macro 1 Entry 10 Digital Joystick Input |
| 0x23A|   1| Profile 1 Macro 1 Entry 11 Digital Joystick Input |
| 0x23B|   1| Profile 1 Macro 1 Entry 12 Digital Joystick Input |
| 0x23C|   1| Profile 1 Macro 1 Entry 13 Digital Joystick Input |
| 0x23D|   1| Profile 1 Macro 1 Entry 14 Digital Joystick Input |
| 0x23E|   1| Profile 1 Macro 1 Entry 15 Digital Joystick Input |
| 0x23F|   1| Profile 1 Macro 1 Entry 16 Digital Joystick Input |
| 0x240|   1| Profile 1 Macro 1 Entry 17 Digital Joystick Input |
| 0x241|   1| Profile 1 Macro 1 Entry 18 Digital Joystick Input |
| 0x242|   1| Profile 1 Macro 1 Entry Total Count               |
| 0x244|   4| Profile 1 Macro 2 Button Assignment               | 
| 0x248|   2| Profile 1 Macro 2 Entry 1 Hold Interval           |
| 0x24A|   2| Profile 1 Macro 2 Entry 2 Hold Interval           |
| 0x24C|   2| Profile 1 Macro 2 Entry 3 Hold Interval           |
| 0x24E|   2| Profile 1 Macro 2 Entry 4 Hold Interval           |
| 0x250|   2| Profile 1 Macro 2 Entry 5 Hold Interval           |
| 0x252|   2| Profile 1 Macro 2 Entry 6 Hold Interval           |
| 0x254|   2| Profile 1 Macro 2 Entry 7 Hold Interval           |
| 0x256|   2| Profile 1 Macro 2 Entry 8 Hold Interval           |
| 0x258|   2| Profile 1 Macro 2 Entry 9 Hold Interval           |
| 0x25A|   2| Profile 1 Macro 2 Entry 10 Hold Interval          |
| 0x25C|   2| Profile 1 Macro 2 Entry 11 Hold Interval          |
| 0x25E|   2| Profile 1 Macro 2 Entry 12 Hold Interval          |
| 0x260|   2| Profile 1 Macro 2 Entry 13 Hold Interval          |
| 0x262|   2| Profile 1 Macro 2 Entry 14 Hold Interval          |
| 0x264|   2| Profile 1 Macro 2 Entry 15 Hold Interval          |
| 0x266|   2| Profile 1 Macro 2 Entry 16 Hold Interval          |
| 0x268|   2| Profile 1 Macro 2 Entry 17 Hold Interval          |
| 0x26A|   2| Profile 1 Macro 2 Entry 18 Hold Interval          |
| 0x26C|   2| Profile 1 Macro 2 Entry 1 Button Input            |
| 0x26E|   2| Profile 1 Macro 2 Entry 2 Button Input            |
| 0x270|   2| Profile 1 Macro 2 Entry 3 Button Input            |
| 0x272|   2| Profile 1 Macro 2 Entry 4 Button Input            |
| 0x274|   2| Profile 1 Macro 2 Entry 5 Button Input            |
| 0x276|   2| Profile 1 Macro 2 Entry 6 Button Input            |
| 0x278|   2| Profile 1 Macro 2 Entry 7 Button Input            |
| 0x27A|   2| Profile 1 Macro 2 Entry 8 Button Input            |
| 0x27C|   2| Profile 1 Macro 2 Entry 9 Button Input            |
| 0x27E|   2| Profile 1 Macro 2 Entry 10 Button Input           |
| 0x280|   2| Profile 1 Macro 2 Entry 11 Button Input           |
| 0x282|   2| Profile 1 Macro 2 Entry 12 Button Input           |
| 0x284|   2| Profile 1 Macro 2 Entry 13 Button Input           |
| 0x286|   2| Profile 1 Macro 2 Entry 14 Button Input           |
| 0x288|   2| Profile 1 Macro 2 Entry 15 Button Input           |
| 0x28A|   2| Profile 1 Macro 2 Entry 16 Button Input           |
| 0x28C|   2| Profile 1 Macro 2 Entry 17 Button Input           |
| 0x28E|   2| Profile 1 Macro 2 Entry 18 Button Input           |
| 0x290|   1| Profile 1 Macro 2 Entry 1 Digital Joystick Input  |
| 0x291|   1| Profile 1 Macro 2 Entry 2 Digital Joystick Input  |
| 0x292|   1| Profile 1 Macro 2 Entry 3 Digital Joystick Input  |
| 0x293|   1| Profile 1 Macro 2 Entry 4 Digital Joystick Input  |
| 0x294|   1| Profile 1 Macro 2 Entry 5 Digital Joystick Input  |
| 0x295|   1| Profile 1 Macro 2 Entry 6 Digital Joystick Input  |
| 0x296|   1| Profile 1 Macro 2 Entry 7 Digital Joystick Input  |
| 0x297|   1| Profile 1 Macro 2 Entry 8 Digital Joystick Input  |
| 0x298|   1| Profile 1 Macro 2 Entry 9 Digital Joystick Input  |
| 0x299|   1| Profile 1 Macro 2 Entry 10 Digital Joystick Input |
| 0x29A|   1| Profile 1 Macro 2 Entry 11 Digital Joystick Input |
| 0x29B|   1| Profile 1 Macro 2 Entry 12 Digital Joystick Input |
| 0x29C|   1| Profile 1 Macro 2 Entry 13 Digital Joystick Input |
| 0x29D|   1| Profile 1 Macro 2 Entry 14 Digital Joystick Input |
| 0x29E|   1| Profile 1 Macro 2 Entry 15 Digital Joystick Input |
| 0x29F|   1| Profile 1 Macro 2 Entry 16 Digital Joystick Input |
| 0x2A0|   1| Profile 1 Macro 2 Entry 17 Digital Joystick Input |
| 0x2A1|   1| Profile 1 Macro 2 Entry 18 Digital Joystick Input |
| 0x2A2|   1| Profile 1 Macro 2 Entry Total Count               |
| 0x2A4|   4| Profile 1 Macro 3 Button Assignment               | 
| 0x2A8|   2| Profile 1 Macro 3 Entry 1 Hold Interval           |
| 0x2AA|   2| Profile 1 Macro 3 Entry 2 Hold Interval           |
| 0x2AC|   2| Profile 1 Macro 3 Entry 3 Hold Interval           |
| 0x2AE|   2| Profile 1 Macro 3 Entry 4 Hold Interval           |
| 0x2B0|   2| Profile 1 Macro 3 Entry 5 Hold Interval           |
| 0x2B2|   2| Profile 1 Macro 3 Entry 6 Hold Interval           |
| 0x2B4|   2| Profile 1 Macro 3 Entry 7 Hold Interval           |
| 0x2B6|   2| Profile 1 Macro 3 Entry 8 Hold Interval           |
| 0x2B8|   2| Profile 1 Macro 3 Entry 9 Hold Interval           |
| 0x2BA|   2| Profile 1 Macro 3 Entry 10 Hold Interval          |
| 0x2BC|   2| Profile 1 Macro 3 Entry 11 Hold Interval          |
| 0x2BE|   2| Profile 1 Macro 3 Entry 12 Hold Interval          |
| 0x2C0|   2| Profile 1 Macro 3 Entry 13 Hold Interval          |
| 0x2C2|   2| Profile 1 Macro 3 Entry 14 Hold Interval          |
| 0x2C4|   2| Profile 1 Macro 3 Entry 15 Hold Interval          |
| 0x2C6|   2| Profile 1 Macro 3 Entry 16 Hold Interval          |
| 0x2C8|   2| Profile 1 Macro 3 Entry 17 Hold Interval          |
| 0x2CA|   2| Profile 1 Macro 3 Entry 18 Hold Interval          |
| 0x2CC|   2| Profile 1 Macro 3 Entry 1 Button Input            |
| 0x2CE|   2| Profile 1 Macro 3 Entry 2 Button Input            |
| 0x2D0|   2| Profile 1 Macro 3 Entry 3 Button Input            |
| 0x2D2|   2| Profile 1 Macro 3 Entry 4 Button Input            |
| 0x2D4|   2| Profile 1 Macro 3 Entry 5 Button Input            |
| 0x2D6|   2| Profile 1 Macro 3 Entry 6 Button Input            |
| 0x2D8|   2| Profile 1 Macro 3 Entry 7 Button Input            |
| 0x2DA|   2| Profile 1 Macro 3 Entry 8 Button Input            |
| 0x2DC|   2| Profile 1 Macro 3 Entry 9 Button Input            |
| 0x2DE|   2| Profile 1 Macro 3 Entry 10 Button Input           |
| 0x2E0|   2| Profile 1 Macro 3 Entry 11 Button Input           |
| 0x2E2|   2| Profile 1 Macro 3 Entry 12 Button Input           |
| 0x2E4|   2| Profile 1 Macro 3 Entry 13 Button Input           |
| 0x2E6|   2| Profile 1 Macro 3 Entry 14 Button Input           |
| 0x2E8|   2| Profile 1 Macro 3 Entry 15 Button Input           |
| 0x2EA|   2| Profile 1 Macro 3 Entry 16 Button Input           |
| 0x2EC|   2| Profile 1 Macro 3 Entry 17 Button Input           |
| 0x2EE|   2| Profile 1 Macro 3 Entry 18 Button Input           |
| 0x2F0|   1| Profile 1 Macro 3 Entry 1 Digital Joystick Input  |
| 0x2F1|   1| Profile 1 Macro 3 Entry 2 Digital Joystick Input  |
| 0x2F2|   1| Profile 1 Macro 3 Entry 3 Digital Joystick Input  |
| 0x2F3|   1| Profile 1 Macro 3 Entry 4 Digital Joystick Input  |
| 0x2F4|   1| Profile 1 Macro 3 Entry 5 Digital Joystick Input  |
| 0x2F5|   1| Profile 1 Macro 3 Entry 6 Digital Joystick Input  |
| 0x2F6|   1| Profile 1 Macro 3 Entry 7 Digital Joystick Input  |
| 0x2F7|   1| Profile 1 Macro 3 Entry 8 Digital Joystick Input  |
| 0x2F8|   1| Profile 1 Macro 3 Entry 9 Digital Joystick Input  |
| 0x2F9|   1| Profile 1 Macro 3 Entry 10 Digital Joystick Input |
| 0x2FA|   1| Profile 1 Macro 3 Entry 11 Digital Joystick Input |
| 0x2FB|   1| Profile 1 Macro 3 Entry 12 Digital Joystick Input |
| 0x2FC|   1| Profile 1 Macro 3 Entry 13 Digital Joystick Input |
| 0x2FD|   1| Profile 1 Macro 3 Entry 14 Digital Joystick Input |
| 0x2FE|   1| Profile 1 Macro 3 Entry 15 Digital Joystick Input |
| 0x2FF|   1| Profile 1 Macro 3 Entry 16 Digital Joystick Input |
| 0x300|   1| Profile 1 Macro 3 Entry 17 Digital Joystick Input |
| 0x301|   1| Profile 1 Macro 3 Entry 18 Digital Joystick Input |
| 0x302|   1| Profile 1 Macro 3 Entry Total Count               |
| 0x304|   4| Profile 1 Macro 4 Button Assignment               | 
| 0x308|   2| Profile 1 Macro 4 Entry 1 Hold Interval           |
| 0x30A|   2| Profile 1 Macro 4 Entry 2 Hold Interval           |
| 0x30C|   2| Profile 1 Macro 4 Entry 3 Hold Interval           |
| 0x30E|   2| Profile 1 Macro 4 Entry 4 Hold Interval           |
| 0x310|   2| Profile 1 Macro 4 Entry 5 Hold Interval           |
| 0x312|   2| Profile 1 Macro 4 Entry 6 Hold Interval           |
| 0x314|   2| Profile 1 Macro 4 Entry 7 Hold Interval           |
| 0x316|   2| Profile 1 Macro 4 Entry 8 Hold Interval           |
| 0x318|   2| Profile 1 Macro 4 Entry 9 Hold Interval           |
| 0x31A|   2| Profile 1 Macro 4 Entry 10 Hold Interval          |
| 0x31C|   2| Profile 1 Macro 4 Entry 11 Hold Interval          |
| 0x31E|   2| Profile 1 Macro 4 Entry 12 Hold Interval          |
| 0x320|   2| Profile 1 Macro 4 Entry 13 Hold Interval          |
| 0x322|   2| Profile 1 Macro 4 Entry 14 Hold Interval          |
| 0x324|   2| Profile 1 Macro 4 Entry 15 Hold Interval          |
| 0x326|   2| Profile 1 Macro 4 Entry 16 Hold Interval          |
| 0x328|   2| Profile 1 Macro 4 Entry 17 Hold Interval          |
| 0x32A|   2| Profile 1 Macro 4 Entry 18 Hold Interval          |
| 0x32C|   2| Profile 1 Macro 4 Entry 1 Button Input            |
| 0x32E|   2| Profile 1 Macro 4 Entry 2 Button Input            |
| 0x330|   2| Profile 1 Macro 4 Entry 3 Button Input            |
| 0x332|   2| Profile 1 Macro 4 Entry 4 Button Input            |
| 0x334|   2| Profile 1 Macro 4 Entry 5 Button Input            |
| 0x336|   2| Profile 1 Macro 4 Entry 6 Button Input            |
| 0x338|   2| Profile 1 Macro 4 Entry 7 Button Input            |
| 0x33A|   2| Profile 1 Macro 4 Entry 8 Button Input            |
| 0x33C|   2| Profile 1 Macro 4 Entry 9 Button Input            |
| 0x33E|   2| Profile 1 Macro 4 Entry 10 Button Input           |
| 0x340|   2| Profile 1 Macro 4 Entry 11 Button Input           |
| 0x342|   2| Profile 1 Macro 4 Entry 12 Button Input           |
| 0x344|   2| Profile 1 Macro 4 Entry 13 Button Input           |
| 0x346|   2| Profile 1 Macro 4 Entry 14 Button Input           |
| 0x348|   2| Profile 1 Macro 4 Entry 15 Button Input           |
| 0x34A|   2| Profile 1 Macro 4 Entry 16 Button Input           |
| 0x34C|   2| Profile 1 Macro 4 Entry 17 Button Input           |
| 0x34E|   2| Profile 1 Macro 4 Entry 18 Button Input           |
| 0x350|   1| Profile 1 Macro 4 Entry 1 Digital Joystick Input  |
| 0x351|   1| Profile 1 Macro 4 Entry 2 Digital Joystick Input  |
| 0x352|   1| Profile 1 Macro 4 Entry 3 Digital Joystick Input  |
| 0x353|   1| Profile 1 Macro 4 Entry 4 Digital Joystick Input  |
| 0x354|   1| Profile 1 Macro 4 Entry 5 Digital Joystick Input  |
| 0x355|   1| Profile 1 Macro 4 Entry 6 Digital Joystick Input  |
| 0x356|   1| Profile 1 Macro 4 Entry 7 Digital Joystick Input  |
| 0x357|   1| Profile 1 Macro 4 Entry 8 Digital Joystick Input  |
| 0x358|   1| Profile 1 Macro 4 Entry 9 Digital Joystick Input  |
| 0x359|   1| Profile 1 Macro 4 Entry 10 Digital Joystick Input |
| 0x35A|   1| Profile 1 Macro 4 Entry 11 Digital Joystick Input |
| 0x35B|   1| Profile 1 Macro 4 Entry 12 Digital Joystick Input |
| 0x35C|   1| Profile 1 Macro 4 Entry 13 Digital Joystick Input |
| 0x35D|   1| Profile 1 Macro 4 Entry 14 Digital Joystick Input |
| 0x35E|   1| Profile 1 Macro 4 Entry 15 Digital Joystick Input |
| 0x35F|   1| Profile 1 Macro 4 Entry 16 Digital Joystick Input |
| 0x360|   1| Profile 1 Macro 4 Entry 17 Digital Joystick Input |
| 0x361|   1| Profile 1 Macro 4 Entry 18 Digital Joystick Input |
| 0x362|   1| Profile 1 Macro 4 Entry Total Count               |
| 0x364|   4| Profile 2 Macro Enable Flag                       |
| 0x368|   1| Profile 2 Macro Total Count                       |
| 0x36C|   4| Profile 2 Macro 1 Button Assignment               |
| 0x370|   2| Profile 2 Macro 1 Entry 1 Hold Interval           |
| 0x372|   2| Profile 2 Macro 1 Entry 2 Hold Interval           |
| 0x374|   2| Profile 2 Macro 1 Entry 3 Hold Interval           |
| 0x376|   2| Profile 2 Macro 1 Entry 4 Hold Interval           |
| 0x378|   2| Profile 2 Macro 1 Entry 5 Hold Interval           |
| 0x37A|   2| Profile 2 Macro 1 Entry 6 Hold Interval           |
| 0x37C|   2| Profile 2 Macro 1 Entry 7 Hold Interval           |
| 0x37E|   2| Profile 2 Macro 1 Entry 8 Hold Interval           |
| 0x380|   2| Profile 2 Macro 1 Entry 9 Hold Interval           |
| 0x382|   2| Profile 2 Macro 1 Entry 10 Hold Interval          |
| 0x384|   2| Profile 2 Macro 1 Entry 11 Hold Interval          |
| 0x386|   2| Profile 2 Macro 1 Entry 12 Hold Interval          |
| 0x388|   2| Profile 2 Macro 1 Entry 13 Hold Interval          |
| 0x38A|   2| Profile 2 Macro 1 Entry 14 Hold Interval          |
| 0x38C|   2| Profile 2 Macro 1 Entry 15 Hold Interval          |
| 0x38E|   2| Profile 2 Macro 1 Entry 16 Hold Interval          |
| 0x390|   2| Profile 2 Macro 1 Entry 17 Hold Interval          |
| 0x392|   2| Profile 2 Macro 1 Entry 18 Hold Interval          |
| 0x394|   2| Profile 2 Macro 1 Entry 1 Button Input            |
| 0x396|   2| Profile 2 Macro 1 Entry 2 Button Input            |
| 0x398|   2| Profile 2 Macro 1 Entry 3 Button Input            |
| 0x39A|   2| Profile 2 Macro 1 Entry 4 Button Input            |
| 0x39C|   2| Profile 2 Macro 1 Entry 5 Button Input            |
| 0x39E|   2| Profile 2 Macro 1 Entry 6 Button Input            |
| 0x3A0|   2| Profile 2 Macro 1 Entry 7 Button Input            |
| 0x3A2|   2| Profile 2 Macro 1 Entry 8 Button Input            |
| 0x3A4|   2| Profile 2 Macro 1 Entry 9 Button Input            |
| 0x3A6|   2| Profile 2 Macro 1 Entry 10 Button Input           |
| 0x3A8|   2| Profile 2 Macro 1 Entry 11 Button Input           |
| 0x3AA|   2| Profile 2 Macro 1 Entry 12 Button Input           |
| 0x3AC|   2| Profile 2 Macro 1 Entry 13 Button Input           |
| 0x3AE|   2| Profile 2 Macro 1 Entry 14 Button Input           |
| 0x3B0|   2| Profile 2 Macro 1 Entry 15 Button Input           |
| 0x3B2|   2| Profile 2 Macro 1 Entry 16 Button Input           |
| 0x3B4|   2| Profile 2 Macro 1 Entry 17 Button Input           |
| 0x3B6|   2| Profile 2 Macro 1 Entry 18 Button Input           |
| 0x3B8|   1| Profile 2 Macro 1 Entry 1 Digital Joystick Input  |
| 0x3B9|   1| Profile 2 Macro 1 Entry 2 Digital Joystick Input  |
| 0x3BA|   1| Profile 2 Macro 1 Entry 3 Digital Joystick Input  |
| 0x3BB|   1| Profile 2 Macro 1 Entry 4 Digital Joystick Input  |
| 0x3BC|   1| Profile 2 Macro 1 Entry 5 Digital Joystick Input  |
| 0x3BD|   1| Profile 2 Macro 1 Entry 6 Digital Joystick Input  |
| 0x3BE|   1| Profile 2 Macro 1 Entry 7 Digital Joystick Input  |
| 0x3BF|   1| Profile 2 Macro 1 Entry 8 Digital Joystick Input  |
| 0x3C0|   1| Profile 2 Macro 1 Entry 9 Digital Joystick Input  |
| 0x3C1|   1| Profile 2 Macro 1 Entry 10 Digital Joystick Input |
| 0x3C2|   1| Profile 2 Macro 1 Entry 11 Digital Joystick Input |
| 0x3C3|   1| Profile 2 Macro 1 Entry 12 Digital Joystick Input |
| 0x3C4|   1| Profile 2 Macro 1 Entry 13 Digital Joystick Input |
| 0x3C5|   1| Profile 2 Macro 1 Entry 14 Digital Joystick Input |
| 0x3C6|   1| Profile 2 Macro 1 Entry 15 Digital Joystick Input |
| 0x3C7|   1| Profile 2 Macro 1 Entry 16 Digital Joystick Input |
| 0x3C8|   1| Profile 2 Macro 1 Entry 17 Digital Joystick Input |
| 0x3C9|   1| Profile 2 Macro 1 Entry 18 Digital Joystick Input |
| 0x3CA|   1| Profile 2 Macro 1 Entry Total Count               |
| 0x3CC|   4| Profile 2 Macro 2 Button Assignment               | 
| 0x3D0|   2| Profile 2 Macro 2 Entry 1 Hold Interval           |
| 0x3D2|   2| Profile 2 Macro 2 Entry 2 Hold Interval           |
| 0x3D4|   2| Profile 2 Macro 2 Entry 3 Hold Interval           |
| 0x3D6|   2| Profile 2 Macro 2 Entry 4 Hold Interval           |
| 0x3D8|   2| Profile 2 Macro 2 Entry 5 Hold Interval           |
| 0x3DA|   2| Profile 2 Macro 2 Entry 6 Hold Interval           |
| 0x3DC|   2| Profile 2 Macro 2 Entry 7 Hold Interval           |
| 0x3DE|   2| Profile 2 Macro 2 Entry 8 Hold Interval           |
| 0x3E0|   2| Profile 2 Macro 2 Entry 9 Hold Interval           |
| 0x3E2|   2| Profile 2 Macro 2 Entry 10 Hold Interval          |
| 0x3E4|   2| Profile 2 Macro 2 Entry 11 Hold Interval          |
| 0x3E6|   2| Profile 2 Macro 2 Entry 12 Hold Interval          |
| 0x3E8|   2| Profile 2 Macro 2 Entry 13 Hold Interval          |
| 0x3EA|   2| Profile 2 Macro 2 Entry 14 Hold Interval          |
| 0x3EC|   2| Profile 2 Macro 2 Entry 15 Hold Interval          |
| 0x3EE|   2| Profile 2 Macro 2 Entry 16 Hold Interval          |
| 0x3F0|   2| Profile 2 Macro 2 Entry 17 Hold Interval          |
| 0x3F2|   2| Profile 2 Macro 2 Entry 18 Hold Interval          |
| 0x3F4|   2| Profile 2 Macro 2 Entry 1 Button Input            |
| 0x3F6|   2| Profile 2 Macro 2 Entry 2 Button Input            |
| 0x3F8|   2| Profile 2 Macro 2 Entry 3 Button Input            |
| 0x3FA|   2| Profile 2 Macro 2 Entry 4 Button Input            |
| 0x3FC|   2| Profile 2 Macro 2 Entry 5 Button Input            |
| 0x3FE|   2| Profile 2 Macro 2 Entry 6 Button Input            |
| 0x400|   2| Profile 2 Macro 2 Entry 7 Button Input            |
| 0x402|   2| Profile 2 Macro 2 Entry 8 Button Input            |
| 0x404|   2| Profile 2 Macro 2 Entry 9 Button Input            |
| 0x406|   2| Profile 2 Macro 2 Entry 10 Button Input           |
| 0x408|   2| Profile 2 Macro 2 Entry 11 Button Input           |
| 0x40A|   2| Profile 2 Macro 2 Entry 12 Button Input           |
| 0x40C|   2| Profile 2 Macro 2 Entry 13 Button Input           |
| 0x40E|   2| Profile 2 Macro 2 Entry 14 Button Input           |
| 0x3B0|   2| Profile 2 Macro 2 Entry 15 Button Input           |
| 0x412|   2| Profile 2 Macro 2 Entry 16 Button Input           |
| 0x414|   2| Profile 2 Macro 2 Entry 17 Button Input           |
| 0x416|   2| Profile 2 Macro 2 Entry 18 Button Input           |
| 0x418|   1| Profile 2 Macro 2 Entry 1 Digital Joystick Input  |
| 0x419|   1| Profile 2 Macro 2 Entry 2 Digital Joystick Input  |
| 0x41A|   1| Profile 2 Macro 2 Entry 3 Digital Joystick Input  |
| 0x41B|   1| Profile 2 Macro 2 Entry 4 Digital Joystick Input  |
| 0x41C|   1| Profile 2 Macro 2 Entry 5 Digital Joystick Input  |
| 0x41D|   1| Profile 2 Macro 2 Entry 6 Digital Joystick Input  |
| 0x41E|   1| Profile 2 Macro 2 Entry 7 Digital Joystick Input  |
| 0x41F|   1| Profile 2 Macro 2 Entry 8 Digital Joystick Input  |
| 0x420|   1| Profile 2 Macro 2 Entry 9 Digital Joystick Input  |
| 0x421|   1| Profile 2 Macro 2 Entry 10 Digital Joystick Input |
| 0x422|   1| Profile 2 Macro 2 Entry 11 Digital Joystick Input |
| 0x423|   1| Profile 2 Macro 2 Entry 12 Digital Joystick Input |
| 0x424|   1| Profile 2 Macro 2 Entry 13 Digital Joystick Input |
| 0x425|   1| Profile 2 Macro 2 Entry 14 Digital Joystick Input |
| 0x426|   1| Profile 2 Macro 2 Entry 15 Digital Joystick Input |
| 0x427|   1| Profile 2 Macro 2 Entry 16 Digital Joystick Input |
| 0x428|   1| Profile 2 Macro 2 Entry 17 Digital Joystick Input |
| 0x429|   1| Profile 2 Macro 2 Entry 18 Digital Joystick Input |
| 0x42A|   1| Profile 2 Macro 2 Entry Total Count               |
| 0x42C|   4| Profile 2 Macro 3 Button Assignment               | 
| 0x430|   2| Profile 2 Macro 3 Entry 1 Hold Interval           |
| 0x432|   2| Profile 2 Macro 3 Entry 2 Hold Interval           |
| 0x434|   2| Profile 2 Macro 3 Entry 3 Hold Interval           |
| 0x436|   2| Profile 2 Macro 3 Entry 4 Hold Interval           |
| 0x438|   2| Profile 2 Macro 3 Entry 5 Hold Interval           |
| 0x43A|   2| Profile 2 Macro 3 Entry 6 Hold Interval           |
| 0x43C|   2| Profile 2 Macro 3 Entry 7 Hold Interval           |
| 0x43E|   2| Profile 2 Macro 3 Entry 8 Hold Interval           |
| 0x440|   2| Profile 2 Macro 3 Entry 9 Hold Interval           |
| 0x442|   2| Profile 2 Macro 3 Entry 10 Hold Interval          |
| 0x444|   2| Profile 2 Macro 3 Entry 11 Hold Interval          |
| 0x446|   2| Profile 2 Macro 3 Entry 12 Hold Interval          |
| 0x448|   2| Profile 2 Macro 3 Entry 13 Hold Interval          |
| 0x44A|   2| Profile 2 Macro 3 Entry 14 Hold Interval          |
| 0x44C|   2| Profile 2 Macro 3 Entry 15 Hold Interval          |
| 0x44E|   2| Profile 2 Macro 3 Entry 16 Hold Interval          |
| 0x450|   2| Profile 2 Macro 3 Entry 17 Hold Interval          |
| 0x452|   2| Profile 2 Macro 3 Entry 18 Hold Interval          |
| 0x454|   2| Profile 2 Macro 3 Entry 1 Button Input            |
| 0x456|   2| Profile 2 Macro 3 Entry 2 Button Input            |
| 0x458|   2| Profile 2 Macro 3 Entry 3 Button Input            |
| 0x45A|   2| Profile 2 Macro 3 Entry 4 Button Input            |
| 0x45C|   2| Profile 2 Macro 3 Entry 5 Button Input            |
| 0x45E|   2| Profile 2 Macro 3 Entry 6 Button Input            |
| 0x460|   2| Profile 2 Macro 3 Entry 7 Button Input            |
| 0x462|   2| Profile 2 Macro 3 Entry 8 Button Input            |
| 0x464|   2| Profile 2 Macro 3 Entry 9 Button Input            |
| 0x466|   2| Profile 2 Macro 3 Entry 10 Button Input           |
| 0x468|   2| Profile 2 Macro 3 Entry 11 Button Input           |
| 0x46A|   2| Profile 2 Macro 3 Entry 12 Button Input           |
| 0x46C|   2| Profile 2 Macro 3 Entry 13 Button Input           |
| 0x46E|   2| Profile 2 Macro 3 Entry 14 Button Input           |
| 0x470|   2| Profile 2 Macro 3 Entry 15 Button Input           |
| 0x472|   2| Profile 2 Macro 3 Entry 16 Button Input           |
| 0x474|   2| Profile 2 Macro 3 Entry 17 Button Input           |
| 0x476|   2| Profile 2 Macro 3 Entry 18 Button Input           |
| 0x478|   1| Profile 2 Macro 3 Entry 1 Digital Joystick Input  |
| 0x479|   1| Profile 2 Macro 3 Entry 2 Digital Joystick Input  |
| 0x47A|   1| Profile 2 Macro 3 Entry 3 Digital Joystick Input  |
| 0x47B|   1| Profile 2 Macro 3 Entry 4 Digital Joystick Input  |
| 0x47C|   1| Profile 2 Macro 3 Entry 5 Digital Joystick Input  |
| 0x47D|   1| Profile 2 Macro 3 Entry 6 Digital Joystick Input  |
| 0x47E|   1| Profile 2 Macro 3 Entry 7 Digital Joystick Input  |
| 0x47F|   1| Profile 2 Macro 3 Entry 8 Digital Joystick Input  |
| 0x480|   1| Profile 2 Macro 3 Entry 9 Digital Joystick Input  |
| 0x481|   1| Profile 2 Macro 3 Entry 10 Digital Joystick Input |
| 0x482|   1| Profile 2 Macro 3 Entry 11 Digital Joystick Input |
| 0x483|   1| Profile 2 Macro 3 Entry 12 Digital Joystick Input |
| 0x484|   1| Profile 2 Macro 3 Entry 13 Digital Joystick Input |
| 0x485|   1| Profile 2 Macro 3 Entry 14 Digital Joystick Input |
| 0x486|   1| Profile 2 Macro 3 Entry 15 Digital Joystick Input |
| 0x487|   1| Profile 2 Macro 3 Entry 16 Digital Joystick Input |
| 0x488|   1| Profile 2 Macro 3 Entry 17 Digital Joystick Input |
| 0x489|   1| Profile 2 Macro 3 Entry 18 Digital Joystick Input |
| 0x48A|   1| Profile 2 Macro 3 Entry Total Count               |
| 0x48C|   4| Profile 2 Macro 4 Button Assignment               | 
| 0x490|   2| Profile 2 Macro 4 Entry 1 Hold Interval           |
| 0x492|   2| Profile 2 Macro 4 Entry 2 Hold Interval           |
| 0x494|   2| Profile 2 Macro 4 Entry 3 Hold Interval           |
| 0x496|   2| Profile 2 Macro 4 Entry 4 Hold Interval           |
| 0x498|   2| Profile 2 Macro 4 Entry 5 Hold Interval           |
| 0x49A|   2| Profile 2 Macro 4 Entry 6 Hold Interval           |
| 0x49C|   2| Profile 2 Macro 4 Entry 7 Hold Interval           |
| 0x49E|   2| Profile 2 Macro 4 Entry 8 Hold Interval           |
| 0x4A0|   2| Profile 2 Macro 4 Entry 9 Hold Interval           |
| 0x4A2|   2| Profile 2 Macro 4 Entry 10 Hold Interval          |
| 0x4A4|   2| Profile 2 Macro 4 Entry 11 Hold Interval          |
| 0x4A6|   2| Profile 2 Macro 4 Entry 12 Hold Interval          |
| 0x4A8|   2| Profile 2 Macro 4 Entry 13 Hold Interval          |
| 0x4AA|   2| Profile 2 Macro 4 Entry 14 Hold Interval          |
| 0x4AC|   2| Profile 2 Macro 4 Entry 15 Hold Interval          |
| 0x4AE|   2| Profile 2 Macro 4 Entry 16 Hold Interval          |
| 0x4B0|   2| Profile 2 Macro 4 Entry 17 Hold Interval          |
| 0x4B2|   2| Profile 2 Macro 4 Entry 18 Hold Interval          |
| 0x4B4|   2| Profile 2 Macro 4 Entry 1 Button Input            |
| 0x4B6|   2| Profile 2 Macro 4 Entry 2 Button Input            |
| 0x4B8|   2| Profile 2 Macro 4 Entry 3 Button Input            |
| 0x4BA|   2| Profile 2 Macro 4 Entry 4 Button Input            |
| 0x4BC|   2| Profile 2 Macro 4 Entry 5 Button Input            |
| 0x4BE|   2| Profile 2 Macro 4 Entry 6 Button Input            |
| 0x4C0|   2| Profile 2 Macro 4 Entry 7 Button Input            |
| 0x4C2|   2| Profile 2 Macro 4 Entry 8 Button Input            |
| 0x4C4|   2| Profile 2 Macro 4 Entry 9 Button Input            |
| 0x4C6|   2| Profile 2 Macro 4 Entry 10 Button Input           |
| 0x4C8|   2| Profile 2 Macro 4 Entry 11 Button Input           |
| 0x4CA|   2| Profile 2 Macro 4 Entry 12 Button Input           |
| 0x4CC|   2| Profile 2 Macro 4 Entry 13 Button Input           |
| 0x4CE|   2| Profile 2 Macro 4 Entry 14 Button Input           |
| 0x4D0|   2| Profile 2 Macro 4 Entry 15 Button Input           |
| 0x4D2|   2| Profile 2 Macro 4 Entry 16 Button Input           |
| 0x4D4|   2| Profile 2 Macro 4 Entry 17 Button Input           |
| 0x4D6|   2| Profile 2 Macro 4 Entry 18 Button Input           |
| 0x4D8|   1| Profile 2 Macro 4 Entry 1 Digital Joystick Input  |
| 0x4D9|   1| Profile 2 Macro 4 Entry 2 Digital Joystick Input  |
| 0x4DA|   1| Profile 2 Macro 4 Entry 3 Digital Joystick Input  |
| 0x4DB|   1| Profile 2 Macro 4 Entry 4 Digital Joystick Input  |
| 0x4DC|   1| Profile 2 Macro 4 Entry 5 Digital Joystick Input  |
| 0x4DD|   1| Profile 2 Macro 4 Entry 6 Digital Joystick Input  |
| 0x4DE|   1| Profile 2 Macro 4 Entry 7 Digital Joystick Input  |
| 0x4DF|   1| Profile 2 Macro 4 Entry 8 Digital Joystick Input  |
| 0x4E0|   1| Profile 2 Macro 4 Entry 9 Digital Joystick Input  |
| 0x4E1|   1| Profile 2 Macro 4 Entry 10 Digital Joystick Input |
| 0x4E2|   1| Profile 2 Macro 4 Entry 11 Digital Joystick Input |
| 0x4E3|   1| Profile 2 Macro 4 Entry 12 Digital Joystick Input |
| 0x4E4|   1| Profile 2 Macro 4 Entry 13 Digital Joystick Input |
| 0x4E5|   1| Profile 2 Macro 4 Entry 14 Digital Joystick Input |
| 0x4E6|   1| Profile 2 Macro 4 Entry 15 Digital Joystick Input |
| 0x4E7|   1| Profile 2 Macro 4 Entry 16 Digital Joystick Input |
| 0x4E8|   1| Profile 2 Macro 4 Entry 17 Digital Joystick Input |
| 0x4E9|   1| Profile 2 Macro 4 Entry 18 Digital Joystick Input |
| 0x4EA|   1| Profile 2 Macro 4 Entry Total Count               |
| 0x4EC|   4| Profile 3 Macro Enable Flag                       |
| 0x4F0|   1| Profile 3 Macro Total Count                       |
| 0x4F4|   4| Profile 3 Macro 1 Button Assignment               |
| 0x4F8|   2| Profile 3 Macro 1 Entry 1 Hold Interval           |
| 0x4FA|   2| Profile 3 Macro 1 Entry 2 Hold Interval           |
| 0x4FC|   2| Profile 3 Macro 1 Entry 3 Hold Interval           |
| 0x4FE|   2| Profile 3 Macro 1 Entry 4 Hold Interval           |
| 0x500|   2| Profile 3 Macro 1 Entry 5 Hold Interval           |
| 0x502|   2| Profile 3 Macro 1 Entry 6 Hold Interval           |
| 0x504|   2| Profile 3 Macro 1 Entry 7 Hold Interval           |
| 0x506|   2| Profile 3 Macro 1 Entry 8 Hold Interval           |
| 0x508|   2| Profile 3 Macro 1 Entry 9 Hold Interval           |
| 0x50A|   2| Profile 3 Macro 1 Entry 10 Hold Interval          |
| 0x50C|   2| Profile 3 Macro 1 Entry 11 Hold Interval          |
| 0x50E|   2| Profile 3 Macro 1 Entry 12 Hold Interval          |
| 0x200|   2| Profile 3 Macro 1 Entry 13 Hold Interval          |
| 0x512|   2| Profile 3 Macro 1 Entry 14 Hold Interval          |
| 0x514|   2| Profile 3 Macro 1 Entry 15 Hold Interval          |
| 0x516|   2| Profile 3 Macro 1 Entry 16 Hold Interval          |
| 0x518|   2| Profile 3 Macro 1 Entry 17 Hold Interval          |
| 0x51A|   2| Profile 3 Macro 1 Entry 18 Hold Interval          |
| 0x51C|   2| Profile 3 Macro 1 Entry 1 Button Input            |
| 0x51E|   2| Profile 3 Macro 1 Entry 2 Button Input            |
| 0x520|   2| Profile 3 Macro 1 Entry 3 Button Input            |
| 0x522|   2| Profile 3 Macro 1 Entry 4 Button Input            |
| 0x524|   2| Profile 3 Macro 1 Entry 5 Button Input            |
| 0x526|   2| Profile 3 Macro 1 Entry 6 Button Input            |
| 0x528|   2| Profile 3 Macro 1 Entry 7 Button Input            |
| 0x52A|   2| Profile 3 Macro 1 Entry 8 Button Input            |
| 0x52C|   2| Profile 3 Macro 1 Entry 9 Button Input            |
| 0x52E|   2| Profile 3 Macro 1 Entry 10 Button Input           |
| 0x530|   2| Profile 3 Macro 1 Entry 11 Button Input           |
| 0x532|   2| Profile 3 Macro 1 Entry 12 Button Input           |
| 0x534|   2| Profile 3 Macro 1 Entry 13 Button Input           |
| 0x536|   2| Profile 3 Macro 1 Entry 14 Button Input           |
| 0x538|   2| Profile 3 Macro 1 Entry 15 Button Input           |
| 0x53A|   2| Profile 3 Macro 1 Entry 16 Button Input           |
| 0x53C|   2| Profile 3 Macro 1 Entry 17 Button Input           |
| 0x53E|   2| Profile 3 Macro 1 Entry 18 Button Input           |
| 0x540|   1| Profile 3 Macro 1 Entry 1 Digital Joystick Input  |
| 0x541|   1| Profile 3 Macro 1 Entry 2 Digital Joystick Input  |
| 0x542|   1| Profile 3 Macro 1 Entry 3 Digital Joystick Input  |
| 0x543|   1| Profile 3 Macro 1 Entry 4 Digital Joystick Input  |
| 0x544|   1| Profile 3 Macro 1 Entry 5 Digital Joystick Input  |
| 0x545|   1| Profile 3 Macro 1 Entry 6 Digital Joystick Input  |
| 0x546|   1| Profile 3 Macro 1 Entry 7 Digital Joystick Input  |
| 0x547|   1| Profile 3 Macro 1 Entry 8 Digital Joystick Input  |
| 0x548|   1| Profile 3 Macro 1 Entry 9 Digital Joystick Input  |
| 0x549|   1| Profile 3 Macro 1 Entry 10 Digital Joystick Input |
| 0x54A|   1| Profile 3 Macro 1 Entry 11 Digital Joystick Input |
| 0x54B|   1| Profile 3 Macro 1 Entry 12 Digital Joystick Input |
| 0x54C|   1| Profile 3 Macro 1 Entry 13 Digital Joystick Input |
| 0x54D|   1| Profile 3 Macro 1 Entry 14 Digital Joystick Input |
| 0x54E|   1| Profile 3 Macro 1 Entry 15 Digital Joystick Input |
| 0x54F|   1| Profile 3 Macro 1 Entry 16 Digital Joystick Input |
| 0x550|   1| Profile 3 Macro 1 Entry 17 Digital Joystick Input |
| 0x551|   1| Profile 3 Macro 1 Entry 18 Digital Joystick Input |
| 0x552|   1| Profile 3 Macro 1 Entry Total Count               |
| 0x554|   4| Profile 3 Macro 2 Button Assignment               |
| 0x558|   2| Profile 3 Macro 2 Entry 1 Hold Interval           |
| 0x55A|   2| Profile 3 Macro 2 Entry 2 Hold Interval           |
| 0x55C|   2| Profile 3 Macro 2 Entry 3 Hold Interval           |
| 0x55E|   2| Profile 3 Macro 2 Entry 4 Hold Interval           |
| 0x560|   2| Profile 3 Macro 2 Entry 5 Hold Interval           |
| 0x562|   2| Profile 3 Macro 2 Entry 6 Hold Interval           |
| 0x564|   2| Profile 3 Macro 2 Entry 7 Hold Interval           |
| 0x566|   2| Profile 3 Macro 2 Entry 8 Hold Interval           |
| 0x568|   2| Profile 3 Macro 2 Entry 9 Hold Interval           |
| 0x56A|   2| Profile 3 Macro 2 Entry 10 Hold Interval          |
| 0x56C|   2| Profile 3 Macro 2 Entry 11 Hold Interval          |
| 0x56E|   2| Profile 3 Macro 2 Entry 12 Hold Interval          |
| 0x570|   2| Profile 3 Macro 2 Entry 13 Hold Interval          |
| 0x572|   2| Profile 3 Macro 2 Entry 14 Hold Interval          |
| 0x574|   2| Profile 3 Macro 2 Entry 15 Hold Interval          |
| 0x576|   2| Profile 3 Macro 2 Entry 16 Hold Interval          |
| 0x578|   2| Profile 3 Macro 2 Entry 17 Hold Interval          |
| 0x57A|   2| Profile 3 Macro 2 Entry 18 Hold Interval          |
| 0x57C|   2| Profile 3 Macro 2 Entry 1 Button Input            |
| 0x57E|   2| Profile 3 Macro 2 Entry 2 Button Input            |
| 0x580|   2| Profile 3 Macro 2 Entry 3 Button Input            |
| 0x582|   2| Profile 3 Macro 2 Entry 4 Button Input            |
| 0x584|   2| Profile 3 Macro 2 Entry 5 Button Input            |
| 0x586|   2| Profile 3 Macro 2 Entry 6 Button Input            |
| 0x588|   2| Profile 3 Macro 2 Entry 7 Button Input            |
| 0x58A|   2| Profile 3 Macro 2 Entry 8 Button Input            |
| 0x58C|   2| Profile 3 Macro 2 Entry 9 Button Input            |
| 0x58E|   2| Profile 3 Macro 2 Entry 10 Button Input           |
| 0x590|   2| Profile 3 Macro 2 Entry 11 Button Input           |
| 0x592|   2| Profile 3 Macro 2 Entry 12 Button Input           |
| 0x594|   2| Profile 3 Macro 2 Entry 13 Button Input           |
| 0x596|   2| Profile 3 Macro 2 Entry 14 Button Input           |
| 0x598|   2| Profile 3 Macro 2 Entry 15 Button Input           |
| 0x59A|   2| Profile 3 Macro 2 Entry 16 Button Input           |
| 0x59C|   2| Profile 3 Macro 2 Entry 17 Button Input           |
| 0x59E|   2| Profile 3 Macro 2 Entry 18 Button Input           |
| 0x5A0|   1| Profile 3 Macro 2 Entry 1 Digital Joystick Input  |
| 0x5A1|   1| Profile 3 Macro 2 Entry 2 Digital Joystick Input  |
| 0x5A2|   1| Profile 3 Macro 2 Entry 3 Digital Joystick Input  |
| 0x5A3|   1| Profile 3 Macro 2 Entry 4 Digital Joystick Input  |
| 0x5A4|   1| Profile 3 Macro 2 Entry 5 Digital Joystick Input  |
| 0x5A5|   1| Profile 3 Macro 2 Entry 6 Digital Joystick Input  |
| 0x5A6|   1| Profile 3 Macro 2 Entry 7 Digital Joystick Input  |
| 0x5A7|   1| Profile 3 Macro 2 Entry 8 Digital Joystick Input  |
| 0x5A8|   1| Profile 3 Macro 2 Entry 9 Digital Joystick Input  |
| 0x5A9|   1| Profile 3 Macro 2 Entry 10 Digital Joystick Input |
| 0x5AA|   1| Profile 3 Macro 2 Entry 11 Digital Joystick Input |
| 0x5AB|   1| Profile 3 Macro 2 Entry 12 Digital Joystick Input |
| 0x5AC|   1| Profile 3 Macro 2 Entry 13 Digital Joystick Input |
| 0x5AD|   1| Profile 3 Macro 2 Entry 14 Digital Joystick Input |
| 0x5AE|   1| Profile 3 Macro 2 Entry 15 Digital Joystick Input |
| 0x5AF|   1| Profile 3 Macro 2 Entry 16 Digital Joystick Input |
| 0x5B0|   1| Profile 3 Macro 2 Entry 17 Digital Joystick Input |
| 0x5B1|   1| Profile 3 Macro 2 Entry 18 Digital Joystick Input |
| 0x5B2|   1| Profile 3 Macro 2 Entry Total Count               |
| 0x5B4|   4| Profile 3 Macro 3 Button Assignment               |
| 0x5B8|   2| Profile 3 Macro 3 Entry 1 Hold Interval           |
| 0x5BA|   2| Profile 3 Macro 3 Entry 2 Hold Interval           |
| 0x5BC|   2| Profile 3 Macro 3 Entry 3 Hold Interval           |
| 0x5BE|   2| Profile 3 Macro 3 Entry 4 Hold Interval           |
| 0x5C0|   2| Profile 3 Macro 3 Entry 5 Hold Interval           |
| 0x5C2|   2| Profile 3 Macro 3 Entry 6 Hold Interval           |
| 0x5C4|   2| Profile 3 Macro 3 Entry 7 Hold Interval           |
| 0x5C6|   2| Profile 3 Macro 3 Entry 8 Hold Interval           |
| 0x5C8|   2| Profile 3 Macro 3 Entry 9 Hold Interval           |
| 0x5CA|   2| Profile 3 Macro 3 Entry 10 Hold Interval          |
| 0x5CC|   2| Profile 3 Macro 3 Entry 11 Hold Interval          |
| 0x5CE|   2| Profile 3 Macro 3 Entry 12 Hold Interval          |
| 0x5D0|   2| Profile 3 Macro 3 Entry 13 Hold Interval          |
| 0x5D2|   2| Profile 3 Macro 3 Entry 14 Hold Interval          |
| 0x5D4|   2| Profile 3 Macro 3 Entry 15 Hold Interval          |
| 0x5D6|   2| Profile 3 Macro 3 Entry 16 Hold Interval          |
| 0x5D8|   2| Profile 3 Macro 3 Entry 17 Hold Interval          |
| 0x5DA|   2| Profile 3 Macro 3 Entry 18 Hold Interval          |
| 0x5DC|   2| Profile 3 Macro 3 Entry 1 Button Input            |
| 0x5DE|   2| Profile 3 Macro 3 Entry 2 Button Input            |
| 0x5E0|   2| Profile 3 Macro 3 Entry 3 Button Input            |
| 0x5E2|   2| Profile 3 Macro 3 Entry 4 Button Input            |
| 0x5E4|   2| Profile 3 Macro 3 Entry 5 Button Input            |
| 0x5E6|   2| Profile 3 Macro 3 Entry 6 Button Input            |
| 0x5E8|   2| Profile 3 Macro 3 Entry 7 Button Input            |
| 0x5EA|   2| Profile 3 Macro 3 Entry 8 Button Input            |
| 0x5EC|   2| Profile 3 Macro 3 Entry 9 Button Input            |
| 0x5EE|   2| Profile 3 Macro 3 Entry 10 Button Input           |
| 0x5F0|   2| Profile 3 Macro 3 Entry 11 Button Input           |
| 0x5F2|   2| Profile 3 Macro 3 Entry 12 Button Input           |
| 0x5F4|   2| Profile 3 Macro 3 Entry 13 Button Input           |
| 0x5F6|   2| Profile 3 Macro 3 Entry 14 Button Input           |
| 0x5F8|   2| Profile 3 Macro 3 Entry 15 Button Input           |
| 0x5FA|   2| Profile 3 Macro 3 Entry 16 Button Input           |
| 0x5FC|   2| Profile 3 Macro 3 Entry 17 Button Input           |
| 0x5FE|   2| Profile 3 Macro 3 Entry 18 Button Input           |
| 0x600|   1| Profile 3 Macro 3 Entry 1 Digital Joystick Input  |
| 0x601|   1| Profile 3 Macro 3 Entry 2 Digital Joystick Input  |
| 0x602|   1| Profile 3 Macro 3 Entry 3 Digital Joystick Input  |
| 0x603|   1| Profile 3 Macro 3 Entry 4 Digital Joystick Input  |
| 0x604|   1| Profile 3 Macro 3 Entry 5 Digital Joystick Input  |
| 0x605|   1| Profile 3 Macro 3 Entry 6 Digital Joystick Input  |
| 0x606|   1| Profile 3 Macro 3 Entry 7 Digital Joystick Input  |
| 0x607|   1| Profile 3 Macro 3 Entry 8 Digital Joystick Input  |
| 0x608|   1| Profile 3 Macro 3 Entry 9 Digital Joystick Input  |
| 0x609|   1| Profile 3 Macro 3 Entry 10 Digital Joystick Input |
| 0x60A|   1| Profile 3 Macro 3 Entry 11 Digital Joystick Input |
| 0x60B|   1| Profile 3 Macro 3 Entry 12 Digital Joystick Input |
| 0x60C|   1| Profile 3 Macro 3 Entry 13 Digital Joystick Input |
| 0x60D|   1| Profile 3 Macro 3 Entry 14 Digital Joystick Input |
| 0x60E|   1| Profile 3 Macro 3 Entry 15 Digital Joystick Input |
| 0x60F|   1| Profile 3 Macro 3 Entry 16 Digital Joystick Input |
| 0x610|   1| Profile 3 Macro 3 Entry 17 Digital Joystick Input |
| 0x611|   1| Profile 3 Macro 3 Entry 18 Digital Joystick Input |
| 0x612|   1| Profile 3 Macro 3 Entry Total Count               |
| 0x614|   4| Profile 3 Macro 4 Button Assignment               |
| 0x618|   2| Profile 3 Macro 4 Entry 1 Hold Interval           |
| 0x61A|   2| Profile 3 Macro 4 Entry 2 Hold Interval           |
| 0x61C|   2| Profile 3 Macro 4 Entry 3 Hold Interval           |
| 0x61E|   2| Profile 3 Macro 4 Entry 4 Hold Interval           |
| 0x620|   2| Profile 3 Macro 4 Entry 5 Hold Interval           |
| 0x622|   2| Profile 3 Macro 4 Entry 6 Hold Interval           |
| 0x624|   2| Profile 3 Macro 4 Entry 7 Hold Interval           |
| 0x626|   2| Profile 3 Macro 4 Entry 8 Hold Interval           |
| 0x628|   2| Profile 3 Macro 4 Entry 9 Hold Interval           |
| 0x62A|   2| Profile 3 Macro 4 Entry 10 Hold Interval          |
| 0x62C|   2| Profile 3 Macro 4 Entry 11 Hold Interval          |
| 0x62E|   2| Profile 3 Macro 4 Entry 12 Hold Interval          |
| 0x630|   2| Profile 3 Macro 4 Entry 13 Hold Interval          |
| 0x632|   2| Profile 3 Macro 4 Entry 14 Hold Interval          |
| 0x634|   2| Profile 3 Macro 4 Entry 15 Hold Interval          |
| 0x636|   2| Profile 3 Macro 4 Entry 16 Hold Interval          |
| 0x638|   2| Profile 3 Macro 4 Entry 17 Hold Interval          |
| 0x63A|   2| Profile 3 Macro 4 Entry 18 Hold Interval          |
| 0x63C|   2| Profile 3 Macro 4 Entry 1 Button Input            |
| 0x63E|   2| Profile 3 Macro 4 Entry 2 Button Input            |
| 0x640|   2| Profile 3 Macro 4 Entry 3 Button Input            |
| 0x642|   2| Profile 3 Macro 4 Entry 4 Button Input            |
| 0x644|   2| Profile 3 Macro 4 Entry 5 Button Input            |
| 0x646|   2| Profile 3 Macro 4 Entry 6 Button Input            |
| 0x648|   2| Profile 3 Macro 4 Entry 7 Button Input            |
| 0x64A|   2| Profile 3 Macro 4 Entry 8 Button Input            |
| 0x64C|   2| Profile 3 Macro 4 Entry 9 Button Input            |
| 0x64E|   2| Profile 3 Macro 4 Entry 10 Button Input           |
| 0x650|   2| Profile 3 Macro 4 Entry 11 Button Input           |
| 0x652|   2| Profile 3 Macro 4 Entry 12 Button Input           |
| 0x654|   2| Profile 3 Macro 4 Entry 13 Button Input           |
| 0x656|   2| Profile 3 Macro 4 Entry 14 Button Input           |
| 0x658|   2| Profile 3 Macro 4 Entry 15 Button Input           |
| 0x65A|   2| Profile 3 Macro 4 Entry 16 Button Input           |
| 0x65C|   2| Profile 3 Macro 4 Entry 17 Button Input           |
| 0x65E|   2| Profile 3 Macro 4 Entry 18 Button Input           |
| 0x660|   1| Profile 3 Macro 4 Entry 1 Digital Joystick Input  |
| 0x661|   1| Profile 3 Macro 4 Entry 2 Digital Joystick Input  |
| 0x662|   1| Profile 3 Macro 4 Entry 3 Digital Joystick Input  |
| 0x663|   1| Profile 3 Macro 4 Entry 4 Digital Joystick Input  |
| 0x664|   1| Profile 3 Macro 4 Entry 5 Digital Joystick Input  |
| 0x665|   1| Profile 3 Macro 4 Entry 6 Digital Joystick Input  |
| 0x666|   1| Profile 3 Macro 4 Entry 7 Digital Joystick Input  |
| 0x667|   1| Profile 3 Macro 4 Entry 8 Digital Joystick Input  |
| 0x668|   1| Profile 3 Macro 4 Entry 9 Digital Joystick Input  |
| 0x669|   1| Profile 3 Macro 4 Entry 10 Digital Joystick Input |
| 0x66A|   1| Profile 3 Macro 4 Entry 11 Digital Joystick Input |
| 0x66B|   1| Profile 3 Macro 4 Entry 12 Digital Joystick Input |
| 0x66C|   1| Profile 3 Macro 4 Entry 13 Digital Joystick Input |
| 0x66D|   1| Profile 3 Macro 4 Entry 14 Digital Joystick Input |
| 0x66E|   1| Profile 3 Macro 4 Entry 15 Digital Joystick Input |
| 0x66F|   1| Profile 3 Macro 4 Entry 16 Digital Joystick Input |
| 0x670|   1| Profile 3 Macro 4 Entry 17 Digital Joystick Input |
| 0x671|   1| Profile 3 Macro 4 Entry 18 Digital Joystick Input |
| 0x672|   1| Profile 3 Macro 4 Entry Total Count               |


## Complete byte map of configuration
Listed below is a complete byte map of the configuration data, written 32
bytes per line.  This table can be used to assist editing the configuration
data directly in a hex editor which allows displaying 32 bytes per column.
All cells marked with `-` are padding bytes to align the data structure,
and should probably be set to `0`.

```
       0                               1
       0 1 2 3 4 5 6 7 8 9 A B C D E F 0 1 2 3 4 5 6 7 8 9 A B C D E F
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