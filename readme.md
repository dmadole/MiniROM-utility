# MiniROM-utility

This is the in-ROM utility for the 1802/Mini to program the EEPROM for firmware updates, and also to boot the machine from ROM.

This is standalone code that does not rely on BIOS, so it has self-contained UAR code. This makes it able to be used to recover from a BIOS problem, and also makes it possible to have a fill XMODEM implementaiton on the EF/Q serial port.

