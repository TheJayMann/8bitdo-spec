enum EnableFlag : u32 {
  Disabled = 0,
  Unenabled = 0x20200000,
  Enabled = 0x20200911,
};

struct Header {
  le EnableFlag ProfileFlag[3];
  le u32 CRC16;
  le u16 GamepadMode;
  le u16 CurrentSlot;
};

struct Filename {
  le char16 Filename[16];
};

struct RumbleData {
  le EnableFlag Flag;
  le float Left, Right;
};

struct AnalogRangeData {
  le EnableFlag Flag;
  u8 LeftStart, LeftEnd;
  u8 RightStart, RightEnd;
};

bitfield SpecialFeaturesBitfield {
  LeftStickInvertX: 1;
  LeftStickInvertY: 1;
  RightStickInvertX: 1;
  RightStickInvertY: 1;
  SwapJoysticks: 1;
  padding: 2;
  SwapTriggers: 1;
  SwapDpadAndLeftStick: 1;
  padding: 1;
  SwapTriggersAndRightStick: 1;
  RumbleHighMotionSensitivity: 1;
  padding: 20;
};

struct SpecialFeatures {
  le EnableFlag Flag;
  SpecialFeaturesBitfield SpecialFeatures;
};

enum SingleButton : u32 {
  Empty,
  Start       = 1 <<  0,
  L3          = 1 <<  1,
  R3          = 1 <<  2,
  Select      = 1 <<  3,
  X           = 1 <<  4,
  Y           = 1 <<  5,
  Right       = 1 <<  6,
  Left        = 1 <<  7,
  Down        = 1 <<  8,
  Up          = 1 <<  9,
  L1          = 1 << 10,
  R1          = 1 << 11,
  B           = 1 << 12,
  A           = 1 << 13,
  L2          = 1 << 14,
  R2          = 1 << 15,
  Menu        = 1 << 16,
  Home        = 1 << 17,
  Bluetooth   = 1 << 18,
  Screenshot  = 1 << 22,
  Turbo       = 1 << 23,
  TurboAuto   = 1 << 24,
  P1          = 1 << 25,
  P2          = 1 << 26,
  DynamicSwap = 1 << 27,
};

struct ButtonMapping {
  le EnableFlag Flag;
  le SingleButton A;
  le SingleButton B;
  le SingleButton X;
  le SingleButton Y;
  le SingleButton L;
  le SingleButton R;
  le SingleButton L2;
  le SingleButton R2;
  le SingleButton L3;
  le SingleButton R3;
  le SingleButton Select;
  le SingleButton Start;
  le SingleButton Share;
  le SingleButton Home;
  le SingleButton Up;
  le SingleButton Down;
  le SingleButton Left;
  le SingleButton Right;
  le SingleButton P1;
  le SingleButton P2;
};

bitfield Button {
  Start:  1;
  L3:     1;
  R3:     1;
  Select: 1;
  X:      1;
  Y:      1;
  Right:  1;
  Left:   1;
  Down:   1;
  Up:     1;
  L1:     1;
  R1:     1;
  B:      1;
  A:      1;
  L2:     1;
  R2:     1;
};

bitfield DigitalJoystick {
  LeftStickUp:     1;
  LeftStickDown:   1;
  LeftStickLeft:   1;
  LeftStickRight:  1;
  RightStickUp:    1;
  RightStickDown:  1;
  RightStickLeft:  1;
  RightStickRight: 1;
};

struct Macro {
  le SingleButton AssignedButton;
  le u16 Intervals[18];
  le Button ButtonSets[18];
  DigitalJoystick JoystickSets[18];
  u8 MacroEntrySize;
  padding[1];
};

struct MacroSet {
  le EnableFlag Flag;
  u8 Count;
  padding[3];
  Macro Macros[4];
};

struct Pro2Config {
  Header Header;
  Filename Filenames[3];
  RumbleData Rumble[3];
  AnalogRangeData Joysticks[3];
  AnalogRangeData Triggers[3];
  SpecialFeatures SpecialFeatures[3];
  ButtonMapping ButtonMappings[3];
  MacroSet MacroSets[3];
};

Pro2Config config @ 0;

