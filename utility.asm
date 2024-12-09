;  Copyright 2024, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


          ; I/O pin definitions for the bit-bang serial routines. These are by
          ; default compatible with the 1802/Mini and Pico/Elf machines.

#define NO_GROUP       0                ; hardware defined - do not change

#define UART_DETECT                     ; use uart if no bit-bang cable
#define INIT_CON                        ; initialize console before booting

#define BRMK           bn2              ; branch on serial mark
#define BRSP           b2               ; branch on serial space
#define SEMK           seq              ; set serial mark
#define SESP           req              ; set serial space
#define EXP_PORT       5                ; group i/o expander port
#define EXP_MEMORY                      ; enable expansion memory
#define UART_GROUP     0                ; uart port group
#define UART_DATA      6                ; uart data port
#define UART_STATUS    7                ; uart status/command port
#define RTC_GROUP      1                ; real time clock group
#define RTC_PORT       3                ; real time clock port
#define SET_BAUD       19200            ; bit-bang serial fixed baud rate
#define FREQ_KHZ       4000             ; default processor clock frequency


          ; Unpublished kernel vector points

d_ideread:  equ   0447h
d_idewrite: equ   044ah


#define scall r4
#define sret r5


          ; These are flags in R8.1 used for various purposes in XMODEM.

#define X_FIRST  1                      ; first xmodem packet was received
#define X_WRITE  2                      ; xmodem receive operation is write
#define X_VERIFY 4                      ; xmodem receive operation is verify
#define X_ERROR  8                      ; an eeprom verify error occurred


            org   0300h

initial:    ldi   1fffh.1
            phi   r2
            ldi   1fffh.0
            plo   r2

            sex   r2

            ldi   setscrt.1
            phi   r3
            ldi   setscrt.0
            plo   r3

            sep   r3


          ; Utility is completely self-contained so that it doesn't depend on
          ; BIOS, this makes it more survivable in the event of a BIOS upgrade
          ; problem or other issue. So there are some basic I/O routines that
          ; re-implement as well as SCRT subroutine calling to support them.

setscrt:    ldi   call.1                ; setup r4 for scall
            phi   r4
            ldi   call.0
            plo   r4

            ldi   ret.1                 ; setup r5 for sret
            phi   r5
            ldi   ret.0
            plo   r5

            ldi   read.1
            phi   rf
            ldi   read.0
            plo   rf


          ; Choose and initialize the serial port. If the UART detect option
          ; is set then use the bitbang port if a cable is plugged into it.
          ; Otherwise use the UART if one is present or use bitbang if not.

          #ifdef UART_DETECT
            BRMK  setbits               ; use bitbang if cable is present
          #endif

          #if UART_GROUP
            sex   r3                    ; set proper expander group for uart
            out   EXP_PORT
            db    UART_GROUP
            sex   r2
          #endif

            inp   UART_DATA             ; clear status flags and buffer
            inp   UART_STATUS

            inp   UART_STATUS           ; use bitbang if uart not present
            ani   2fh
            bnz   setbits

            sex   r3                    ; 8 data bits, 1 stop bit, no parity
            out   UART_STATUS
            db    19h

          #if UART_GROUP
            out   EXP_PORT              ; reset to default expander group
            db    NO_GROUP
          #endif

            ldi   0                     ; zero bitrate to signal uart
            phi   re

            ldi   getuart               ; update input vector to uart
            inc   rf
            str   rf

            sex   r2                    ; reset x to stack pointer
            br    continu


          ; If we are using the bitbang port, then set a fixed baud rate if
          ; SET_BAUD is set, otherwise get a keystroke to set autobaud.
          ; Either way we start with setting the line to the idle "mark"
          ; state and waiting until the receive side is idle.

setbits:    SEMK                      ; set idle state for line

timersrt:   ldi   0                   ; Wait to make sure the line is idle,
timeidle:   smi   1                   ;  so we don't try to measure in the
            nop                       ;  middle of a character, we need to
            BRSP  timersrt            ;  get 256 consecutive loops without
            bnz   timeidle            ;  input asserted before this exits

          #ifdef SET_BAUD
            ldi   (FREQ_KHZ*5)/(SET_BAUD/25)-23
            br    timegot
          #endif

timestrt:   BRMK  timestrt            ; Stall here until start bit begins

            nop                       ; Burn a half a loop's time here so
            ldi   1                   ;  that result rounds up if closer

timecnt1:   phi   re                  ; Count up in units of 9 machine cycles
timecnt2:   adi   1                   ;  per each loop, remembering the last
            lbz   timedone            ;  time that input is asserted, the
            BRSP  timecnt1            ;  very last of these will be just
            br    timecnt2            ;  before the start of the stop bit

timedone:   ghi   re                  ; Get timing loop value, subtract
            smi   23                  ;  offset of 23 counts, if less than
            bnf   timersrt            ;  this, then too low, go try again

timegot:    lsz                       ; Fold both 23 and 24 into zero, this
            smi   1                   ;  adj is needed for 9600 at 1.8 Mhz

            phi   re                  ; Got a good measurement, save it

            ldi   putbits             ; update output vector to bit banged
            dec   rf
            str   rf




continu:    sep   scall
            dw    inmsg
            db    13,10,10
            db    'Mini/ROM Utility V.4.0.0'
            db    13,10,0

            br    command





contrlc:    sep   scall
            dw    inmsg
            db    '^C',0

command:    sep   scall
            dw    inmsg
            db    13,10,'> ',0

            ldi   buffer.1
            phi   rf
            ldi   buffer.0
            plo   rf

            ldi   77.0
            plo   rc

            sep   scall
            dw    input
            bdf   contrlc



            sep   scall
            dw    inmsg
            db    13,10,10,0

            ldi   buffer.1
            phi   ra
            phi   rf
            ldi   buffer.0
            plo   ra
            plo   rf


          ; Pre-process the input line to make it easier to parse. All alpha
          ; characters are changed to lower case, any leading and trailing
          ; spaces removed, and the input is broken into words, separated by
          ; zero bytes, and terminate with an extra zero byte.
       
skipini:    lda   ra                    ; skip any leading spaces on line
            bz     gotline
            sdi   ' '
            bdf   skipini

nextchr:    sdi   ' '-'a'               ; fold lower case into upper case
            lsnf
            smi   'a'-'A'
            adi   'a'

            ori   ' '                   ; make lower case and store
            str   rf
            inc   rf

            lda   ra                    ; skip additional word characters
            bz    gotline
            sdi   ' '
            bnf   nextchr

            ldi   0                     ; insert zero into string
            str   rf
            inc   rf

skipspc:    lda   ra                    ; skip any additional spaces
            bz    gotspac
            sdi   ' '
            bdf   skipspc

            br    nextchr               ; get next word in string

gotspac:    dec   rf                    ; if last was space then remove

gotline:    ldi   0                     ; double zero to end the string
            str   rf
            inc   rf
            str   rf


          ; Check the cleaned-up command line buffer agains the list of 
          ; commands one word at a time for a match. A prefix of each word
          ; will be accepted so the table needs to be sorted accorbingly.

            ldi   cmdtabl.1
            phi   rc
            ldi   cmdtabl.0
            plo   rc

            ldi   buffer.1
            phi   rf

            sex   rf


          ; Check one command list entry. If at the end of the list, then
          ; the command line was not matched. Otherwise, the first letter in
          ; each word must match, otherwise skip to the next entry.

chknext:    ldi   buffer
            plo   rf

nxtword:    lda   rc
            lbz   unknown

            sm
            lbnz  skipcmd


          ; Check the remaining letters until either the end of the word in
          ; the command list, or until a mismatched character, which can also
          ; mean the end of the command line word.

strcomp:    inc   rf

            lda   rc
            lbz   endword

            sm
            bz    strcomp


          ; If a mismatch, skip to the end of the command list work, and if
          ; at the end of the command line word, treat as a prefix partial
          ; word match. If at the end of the command list entry, we have a
          ; match, otherwise resume matching with next word.

skpword:    lda   rc
            lbnz  skpword

endword:    lda   rf
            lbnz  chklast

            lda   rc
            bz    matched

            sm
            lbz   strcomp


          ; If a mismatched word, then skip to the next command list entry
          ; and test again from there.

skipcmd:    lda   rc
            bnz   skipcmd

chklast:    lda   rc
            bnz   skipcmd

            inc   rc
            inc   rc

            lbr   chknext


          ; If we have a match, pick up the routine address from the command
          ; list and jump to it. We do this through an intermediate PC.

matched:    sex   r2                    ; set x back to the stack pointer

indjump:    ldi   jump_r3.1             ; temporarily change program counter
            phi   rd
            ldi   jump_r3.0
            plo   rd

            sep   rd                    ; swap program counter to rd

jump_r3:    lda   rc                    ; load routine address into r3
            phi   r3
            lda   rc
            plo   r3

            sep   r3                    ; set program counter back to r3


          ;--------------------------------------------------------------------
          ; If the leading words on the command line cannot be matched to
          ; an entry in the command table, then it is an unknown command.

unknown:    sep   scall
            dw    inmsg
            db    'Unknown command',13,10,0

            lbr   command


          ;--------------------------------------------------------------------
          ; If an argument cannot be parsed, or if there are more arguments
          ; than expected, that that is an argument error.

invalid:    sep   scall
            dw    inmsg
            db    'Invalid argument',13,10,0

            lbr    command


          ;--------------------------------------------------------------------
          ; A list of commands for parsing against the command-line input.
          ; First is a list of words separated by zero bytes, then an extra
          ; zero byte to follow the last word, then the address of the code
          ; that implements that command.

cmdtabl:    db    'rom',0,'write',0,'enable',0,0
            dw    writena

            db    'rom',0,'write',0,'protect',0,0
            dw    writdis

            db    'rom',0,'write',0,0
            dw    romwrit

            db    'rom',0,'verify',0,0
            dw    romvrfy

            db    'rom',0,'test',0,0
            dw    romtest

            db    'rom',0,'checksum',0,0
            dw    romchek

            db    'boot',0,'rom',0,0
            dw    bootrom

            db    'boot',0,'disk',0,0
            dw    bootdsk

            db    'boot',0,0
            dw    bootdsk

            db    'reset',0,0
            dw    doreset

            db    'help',0,0
            dw    helpmsg

            db    0


          ; ------------------------------------------------------------------
          ; Action for "rom test" command, which intiates an XMODEM receive
          ; but does nothing with the file, useful for just testing XMODEM.

romtest:    ldi   0                     ; verify xmodem receive to eeprom
            phi   r8

            sep   scall
            dw    inmsg
            db    'Test',0

            sep   scall                 ; initiate xmodem transfer
            dw    rxmodem

            lbr   command               ; get next command input


          ; ------------------------------------------------------------------
          ; Action for "rom verify" command, which intiates an XMODEM
          ; receive transfer that is verified block-by-block against the
          ; EEPROM.

romvrfy:    ldi   X_VERIFY              ; verify xmodem receive to eeprom
            phi   r8

            sep   scall
            dw    inmsg
            db    'Verify',0

            sep   scall                 ; initiate xmodem transfer
            dw    rxmodem

            lbr   command               ; get next command input


          ; ------------------------------------------------------------------
          ; Action for "rom write" command, which intiates an XMODEM
          ; receive transfer that is programmed to the EEPROM and also
          ; verified block-by-block. The EEPROM is automatically write-
          ; enabled before programming, and write-protected after.

romwrit:    sep   scall                 ; send eeprom command prefix
            dw    sendpre

            sep   scall                 ; send eeprom write enable command
            dw    sendena

            ldi   X_WRITE+X_VERIFY      ; write and verify eeprom
            phi   r8

            sep   scall
            dw    inmsg
            db    'Writ',0

            sep   scall                 ; transfer, fall through to protect
            dw    rxmodem


          ; ------------------------------------------------------------------
          ; Action for "rom write protect" command, which soft-write
          ; protects the XMODEM by sending a magic number sequence.

writdis:    sep   scall                 ; send eeprom command prefix
            dw    sendpre

            sep   scall                 ; send eeprom write protect command
            dw    senddis

            lbr   command               ; get next command input


          ; ------------------------------------------------------------------
          ; Action for "rom write enable" command, which soft-write-enables
          ; the XMODEM by sending a magic number sequence.

writena:    sep   scall
            dw    sendpre

            sep   scall
            dw    sendena

            lbr   command



          ; Calculate the checksum of the ROM from $8000-FFFF

romchek:    sep   scall
            dw    inmsg
            db    'Checksum ',0

            ldi   8000h.1               ; pointer to start of rom
            phi   ra
            ldi   8000h.0
            plo   ra

            ldi   0                     ; clear sum accumulator
            str   r2
            plo   rc
            phi   rc

cheksum:    lda   ra                    ; add next byte into lsb on stack
            add
            str   r2

            ghi   rc

            bnf   nocarry               ; increment msb if carry occurred
            inc   rc

nocarry:    add
            phi   rc

            ghi   ra                    ; loop until address rolls over
            bnz   cheksum

            ldn   r2                    ; save checksum msb
            plo   r8


          ; Move the MSB and LSB into RD.1 and RD.0 where they need to be,
          ; then convert to hex string for output.

            dec   ra                    ; display checksum from rom
            dec   ra

            sep   scall
            dw    hexchek

            ghi   rc
            bnz   chekerr

            sex   ra

            dec   ra
            glo   r8
            sm
            bnz   chekerr

            dec   ra
            glo   rc
            sm
            bnz   chekerr

            sep   scall
            dw    inmsg
            db    ' OK',13,10,0

            lbr   command

chekerr:    sep   scall
            dw    inmsg
            db    ' FAIL',13,10,0

            lbr   command


hexchek:    sep   scall
            dw    hexbyte

hexbyte:    ldn   ra

            shr
            shr
            shr
            shr

            sep   scall
            dw    hexnibl

            lda   ra
            ani   15

hexnibl:    smi   10
            lsnf
            adi   'A'-'0'-10
            adi   '0'+10

            lbr   type


          ; ------------------------------------------------------------------
          ; Action for "help" command which dumps the command parsing table
          ; to display a list of all possible commands.

helpmsg:    ldi   cmdtabl.1
            phi   rf
            ldi   cmdtabl.0
            plo   rf

            br    helpmor

helpspc:    ldi   ' '
            sep   scall
            dw    type

helpmor:    sep   scall
            dw    msg

            ldn   rf
            bnz   helpspc

            inc   rf
            inc   rf
            inc   rf

            sep   scall
            dw    inmsg
            db    13,10,0

            ldn   rf
            lbz   command

            br    helpmor


          ; ------------------------------------------------------------------
          ; Action for "boot disk" command which boots the system from disk
          ; by jumping into the $F000 vector in BIOS which is the default
          ; boot entry point.

bootdsk:    ldi   0f000h.0              ; set lsb and then fall through
            lskp


          ; ------------------------------------------------------------------
          ; Action for "boot rom" command which boots the system from the ROM
          ; disk image by jumping into the $F003 vector in BIOS which is the
          ; alternate boot entry point for this purpose.

bootrom:    ldi   0f003h.0              ; set the entry point address
            plo   r0 
            ldi   0f003h.1
            phi   r0

            sep   scall                 ; display a notice before jumping
            dw    inmsg
            db    'Booting system.',0

            sep   r0                    ; change pc to r0 and jump


          ; ------------------------------------------------------------------
          ; Action for "reset" command which restarts the system as reset
          ; would, at least from a software perspective. This differs from
          ; "boot disk" as it might cause the unlity to get re-entered.

doreset:    sep   scall                 ; display message before going
            dw    inmsg
            db    'Resetting system.',0

            ldi   8000h.1               ; get address of start of rom
            phi   r0
            ldi   8000h.0
            plo   r0

            sep   r0                    ; change pc to r0 and jump


          ; ------------------------------------------------------------------
          ; Send the command prefix to the EEPROM to initiate either a soft
          ; write-protect or write-enable command.

sendpre:    sep   scall                 ; display message
            dw    inmsg
            db    'ROM write ',0

            ldi   55h+80h               ; first magic address for algorithm
            phi   r7
            ldi   55h
            plo   r7

            ldi   2ah+80h               ; second magic address for algorithm
            phi   r8
            ldi   0aah
            plo   r8

            ldi   0aah                  ; 1st write for either: aa->5555
            str   r7

            ldi   055h                  ; 2nd write for either: 55->2aaa
            str   r8

            sep   sret


          ; ------------------------------------------------------------------
          ; Send the command suffix to the EEPROM to soft write-protect.

senddis:    ldi   0a0h                  ; 3rd write for protect: a0->5555
            str   r7

            sep   scall                 ; display message
            dw    inmsg
            db    'protected',13,10,0

            sep   sret                  ; return to caller


          ; ------------------------------------------------------------------
          ; Send the command suffix to the EEPROM to soft write-protect.

sendena:    ldi   080h                  ; 3rd write for unprotect: 80->5555
            str   r7

            ldi   0aah                  ; 4th write for unprotect: aa->5555
            str   r7

            ldi   055h                  ; 5th write for unprotect: 55->2aaa
            str   r8

            ldi   020h                  ; 6th write for unprotect: 20->5555
            str   r7

            sep   scall                 ; display message
            dw    inmsg
            db    'enabled.',13,10,0

            sep   sret                  ; return to caller


          ; ASCII control character definitions used for XMODEM protocol.

#define NUL 0       ; null is used instead of zero
#define SOH 1       ; start-of-header starts 128-byte packet
#define ETX 3       ; end-of-test recognized to cancel (control-c)
#define EOT 4       ; end-of-text is received after all packets
#define ACK 6       ; acknowledge is send following a valid packet
#define NAK 21      ; negative acknowledgement is sent after an error
#define CAN 24      ; cancel to abort transmission and abandon file


          ; ------------------------------------------------------------------

rxmodem:    sep   scall
            dw    inmsg
            db    'ing XMODEM...',0

            ghi   re
            bz    setuart

            ldi   tmobits.0             ; set routines for uart console port
            plo   r7
            ldi   putbits.0
            phi   r7

            br    prepare

setuart:    ldi   tmouart.0             ; set routines for uart console port
            plo   r7
            ldi   putuart.0
            phi   r7


          ; Now that the UART is selected switch up the program counter
          ; and subroutine counter to prepare for transfer.

prepare:    ldi   startit.1             ; switch program counter now to r5
            phi   r5
            ldi   startit.0
            plo   r5

            sep   r5                    ; continues below with p as r5


          ; We are running with R6 as the program counter now. Initialize
          ; the one-time things we need for the transfer.

startit:    ldi   1                     ; first expected packet is one
            plo   r8

            ldi   buffer.1              ; set buffer pointer to start
            phi   rf

            ldi   8000h.1
            phi   ra
            ldi   8000h.0
            plo   ra


          ; All of our subroutines are in the same page so we will set the
          ; high byte of the address into r3 once here, and we will set the
          ; low bytes for send and receive into r7 high and low bytes based
          ; on which interface we are using.

            ldi   getuart.1             ; set msb to the subroutine page
            phi   r3

            glo   r7                    ; set subroutine pointer to input
            plo   r3

            lbr   waitnak

            org   (($-1)|255)+1


          ; Flush the input until nothing has been received for about one
          ; second by calling input repeatedly until it times out. Then fall
          ; though and send a NAK character.

waitnak:    ldi   51                    ; keep getting input until timeout
            sep   r3
            bnf   waitnak


          ; Send a NAK to provoke the sender to either start transmitting or
          ; to resend the last packet because it was in error.
            
sendnak:    ghi   r7                    ; set pointer to send byte routine
            plo   r3

            ldi   NAK                   ; send the NAK to transmitter
            sep   r3


          ; Receive the start of a packet, which for a normal XMODEM packet
          ; will be a SOH character.

recvsoh:    ldi   buffer                ; reset pointer to current buffer
            plo   rf

            ldi   255                   ; get byte, nak if long timeout
            sep   r3
            bdf   sendnak

            xri   SOH^NUL               ; if soh then start of regular packet  
            bz    recvpkt

            xri   EOT^SOH               ; if eot then transfer is all done
            bz    alldone

            xri   ETX^EOT               ; if eot then transfer is all done
            bz    abandon

            xri   CAN^ETX               ; if eot then transfer is all done
            bz    abandon

            br    waitnak               ; any thing else, flush input and nak


          ; Get the block number and block number check byte and save for
          ; checking later. We do this outside of the data read so that it
          ; doesn't clog up the stacking of data segments in the buffer.

recvpkt:    ldi   51                    ; get block number, nak if timeout
            sep   r3
            bdf   sendnak

            plo   r9                    ; save to check later on

            ldi   51                    ; get block check, nak if timeout
            sep   r3
            bdf   sendnak

            phi   r9                    ; save to check later on


          ; Read the 128 data bytes into the buffer. Since the buffer is page-
          ; aligned, the XMODEM blocks will be half-page aligned to we can use
          ; the buffer index as the counter also.

nextpkt:    ldi   51                   ; get data byte, nak if timeout
            sep   r3
            bdf   sendnak

            str   rf                   ; write byte into buffer and advance
            inc   rf

            glo   rf                   ; repeat until at 128 byte boundary
            ani   %1111111
            bnz   nextpkt


          ; Read the final byte of the packet, the checksum. Save this for the
          ; moment, we will check it later when we calculate the checksum.

            ldi   51                   ; get the checksum, nak if timeout
            sep   r3
            bdf   sendnak

            plo   re                   ; save into accumulator for checksum


          ; Check that the block number is valid (the block and block check
          ; are one's complements) and that the block is the one we are 
          ; expecting. As a special case, if we see the prior block again,
          ; send an ACK so that the transmitter will move forward.

            glo   r9                    ; its easier if we add 1 to block
            adi   1
            str   r2

            ghi   r9
            add                         ; if check fails then wait and nak
            bnz   waitnak

            glo   r8                    ; if prior block then wait and ack
            sm
            bz    waitack

            adi   1                     ; if not expected then wait and nak
            bnz   waitnak


          ; Calculate the checksum of the data by subtracting all the data
          ; bytes from the checksum byte. If everything is correct, the result
          ; will be zero. The loop is unrolled by a factor of four for speed.

            ldi   buffer                ; reset pointer to start of packet
            plo   rf

            sex   rf                    ; argument for sm will by data bytes

sumloop:    glo   re                    ; subtrack four data bytes from sum
            sm
            inc   rf
            sm
            inc   rf
            sm
            inc   rf
            sm
            inc   rf
            plo   re

            glo   rf                    ; repeat until 128 byte boundary
            ani   %1111111
            bnz   sumloop

            sex   r2                    ; set x back to r2 stack pointer

            glo   re                    ; error if sum not zero, flush and nak
            bnz   waitnak


          ; If an EEPROM program operation, then write this packet
          ; to EEPROM in block mode (which will take two EEPROM blocks
          ; per XMODEM packet). Fall through to verify each packet.

            ghi   r8                    ; check flag if not first packet
            ani   X_WRITE
            bz    verify

            ldi   buffer                ; reset buffer pointer to start
            plo   rf

            ghi   ra                    ; get pointer to eeprom block
            phi   rd
            glo   ra
            plo   rd

            sex   rd                    ; verify against eeprom data

wrtloop:    lda   rf                    ; program byte to eeprom
            str   rd

            glo   rf                    ; write until end of 64-byte block
            ani   63
            bnz   noblock

wrtwait:    ldn   rd                    ; wait until bit 6 reads same twice
            xor
            ani   64
            bnz   wrtwait

noblock:    inc   rd                    ; advance source and target pointers

            glo   rf                    ; loop until all packet checked
            ani   127
            bnz   wrtloop


          ; Verify packet against EEPROM contents, if failure, then set
          ; the failure mode code into R9.1 but keep going. We can't
          ; interrupt the XMODEM file receive even if there's an error.

verify:     ghi   r8                    ; check flag if not first packet
            ani   X_VERIFY
            bz    nowrite

check:      ldi   buffer                ; set buffer pointer to start
            plo   rf

            ghi   ra                    ; get pointer to eeprom block
            phi   rd
            glo   ra
            plo   rd

            sex   rd                    ; verify against eeprom data

chkloop:    lda   rf                    ; if byte matches, go on to next
            xor
            bz    chkgood

            ghi   r8                    ; else set error and unset verify
            xri   X_VERIFY+X_ERROR
            phi   r8

            br    nowrite               ; abandon rest of this block

chkgood:    inc   rd                    ; advance to next eeprom byte

            glo   rf                    ; loop until all packet checked
            ani   127
            bnz   chkloop


          ; Get ready for the next block: increment the block number and
          ; set the buffer pointer just following the block just received.

nowrite:    sex   r2                    ; point back to stack

            ghi   r8                    ; increment block number
            inc   r8
            phi   r8

            glo   ra                    ; advance to next eeprom block
            adi   127
            plo   ra
            inc   ra


          ; As a special case, that occurs with Tera Term, for example, the
          ; receiving side may queue multiple NAKs before it is ready to 
          ; send, and then send the first packet multiple times as a result.
          ; To help recover from this quickly, flush any remaining input only
          ; after the first packet, using a quick timeout.

            ghi   r8                    ; check flag if not first packet
            ani   X_FIRST
            bnz   sendack

            ghi   r8                    ; if flag not set, set it now
            ori   X_FIRST
            phi   r8

            ldi   10                    ; set a very short timeout then wait
            lskp


          ; If a packet is received that is a duplicate of the last packet,
          ; then some kind of loss or corruption has occurred. To aid in error
          ; recovery, flush any remaining input before sending an ACK.

waitack:    ldi   51                    ; read input until there is no more
            sep   r3
            bnf   waitack


          ; Send an ACK immediately in response to the good packet, and loop
          ; back and get the next packet.

sendack:    ghi   r7                    ; set subroutine pointer to send
            plo   r3

            ldi   ACK                   ; send ack since a good packet
            sep   r3

            br    recvsoh               ; and then get the next packet



abandon:    ldi   msgcanc.1
            phi   rf
            ldi   msgcanc.0
            plo   rf

            br    xreturn


          ; After the last data packet, acknowledge the EOT end marker, then
          ; return back to the normal program counter and SCRT setup for
          ; final file operations and return to kernel.

alldone:    ghi   r7                    ; set subroutine pointer to send
            plo   r3

            ldi   ACK                   ; acknowledge end of packets
            sep   r3

            ghi   r8
            ani   X_ERROR
            bz    noerror

errcomp:    ldi   msgfail.1
            phi   rf
            ldi   msgfail.0
            plo   rf

            br    xreturn

noerror:    ldi   msgcomp.1
            phi   rf
            ldi   msgcomp.0
            plo   rf


          ; Restore the normal SCRT environment by switch PC back to R3 and
          ; resetting R5 to sret routine. Output final status message.

xreturn:    ldi   retrest.1
            phi   r3
            ldi   retrest.0
            plo   r3

            sep   r3

retrest:    ldi   ret.1
            phi   r5
            ldi   ret.0
            plo   r5

            sep   scall
            dw    msg

            sep   sret

msgfail:    db    'VERIFY FAILED.',13,10,0
msgcomp:    db    'succeeded.',13,10,0
msgcanc:    db    'CANCELLED.',13,10,0


          ; Reset the system to the normal SCRT environment by restoring r5
          ; and r3 and resetting the program counter to r3. Also restore the
          ; echo flag in RE.1.


callbr:     glo   re
            sep   r3                    ; jump to called routine

            ; Entry point for CALL here.

call:       plo   re                    ; Save D
            sex   r2

            glo   r6                    ; save last R[6] to stack
            stxd
            ghi   r6
            stxd

            ghi   r3                    ; copy R[3] to R[6]
            phi   r6
            glo   r3
            plo   r6

            lda   r6                    ; get subroutine address
            phi   r3                    ; and put into r3
            lda   r6
            plo   r3

            br    callbr                ; transfer control to subroutine


retbr:      glo   re                    ; restore d and jump to return
            sep   r3                    ;  address taken from r6

            ; Entry point for RET here.

ret:        plo   re                    ; save d and set x to 2
            sex   r2

            ghi   r6                    ; get return address from r6
            phi   r3
            glo   r6
            plo   r3

            irx                         ; restore next-prior return address
            ldxa                        ;  to r6 from stack
            phi   r6
            ldx
            plo   r6

            br    retbr                 ; jump back to continuation








            org   (($-1)|255)+1


input:      ldi   0
            plo   rd

inloop:     sep   scall
            dw    read

            smi   127
            bdf   inloop

            adi   127-32
            bdf   print

            adi   32-13
            bz    cr

            adi   13-8
            bz    bs

            adi   8-3
            bnz   inloop

            ldi   1

cr:         shr
            str   rf

            sep   sret

print:      glo   rc
            bz    inloop

            glo   re
            str   rf

            inc   rf
            inc   rd
            dec   rc

            glo   re
            sep   scall
            dw    type

            br    inloop

bs:         glo   rd
            bz    inloop

            dec   rf
            dec   rd
            inc   rc

            sep   scall
            dw    inmsg
            db    8,32,8,0

            br    inloop


msgloop:    sep   scall
            dw    type

msg:        lda   rf
            bnz   msgloop

            sep   sret


inmloop:    sep   scall
            dw    type

inmsg:      lda   r6
            bnz   inmloop

            sep   sret






          ; ------------------------------------------------------------------
          ; These vectors will be used for general calls for console input
          ; and output via SCRT and will be updated during UART detection
          ; and initialization. We will start with one them pointing to
          ; opposite routines so only one has to be updated. Because all of
          ; the code will be copied to RAM before running, these will be 
          ; able to be updated even though the utility is stored in RAM.

type:       br    putuart
read:       br    getbits


          ; ------------------------------------------------------------------
          ; This implements a receive byte with timeout function for the UART
          ; using BIOS routines by polling with F_UTEST to check if a byte is
          ; received while counting down a timer. To do this all quickly 
          ; enough, a special calling routine is used; see the notes elsewhere
          ; for a detailed explanation.
          ;
          ; The routine is folded on itself so that the return resets the
          ; subroutine instruction pointer back to the beginning of the routine
          ; so that it can quickly be called again.

getuart:    ;;;                         ; can't put a label on #if line

          #if UART_GROUP
            sex   r3
            out   EXP_PORT
            db    UART_GROUP
            sex   r2
          #endif

uartzer:    inp   UART_STATUS           ; wait forever until received
            shr
            bnf   uartzer

uartchr:    inp   UART_DATA             ; read input byte and clear df
            adi   0

uartret:    ;;;                         ; can't put a label on #if line

          #if UART_GROUP
            sex   r3                    ; reset default group if changed
            out   EXP_PORT
            db    NO_GROUP
            sex   r2
          #endif

            sep   sret                  ; return either sep or scall


          ; Entry point to read a byte from the UART with a timeout in RB.

tmouart:    phi   rb                    ; can't put a label on #if line

          #if UART_GROUP
            sex   r3
            out   EXP_PORT
            db    UART_GROUP
            sex   r2
          #endif

            bz    uartzer

uarttst:    inp   UART_STATUS
            shr
            bdf   uartchr

            ldi   6
uartdly:    smi   1
            bnz   uartdly

            dec   rb                    ; else test again if time is not up
            ghi   rb
            bnz   uarttst

            br    uartret


          ; ------------------------------------------------------------------
          ; Send a byte through the UART using the F_UTYPE routine in BIOS.
          ; Aside from the calling convention, this is very simple. Return
          ; through GETUART so that the PC is setup for sending a byte.

putuart:    stxd                        ; save the byte to send
            stxd

          #if UART_GROUP
            sex   r3
            out   EXP_PORT
            db    UART_GROUP
            sex   r2
          #endif

uartrdy:    inp   UART_STATUS
            shl
            bnf   uartrdy

            irx
            out   UART_DATA

            br    uartret               ; return through getuart


          ; ------------------------------------------------------------------
          ; This is a complex update of the Nitro UART from MBIOS; it has been
          ; modified to move the cycles for the bit rate factor decompression
          ; into the time of the start bit to minimize time and allow back-to-
          ; back bytes to be received without having to pre-decompress.
          ;
          ; This version also implements a timeout which is needed for XMODEM.
          ; The timeout value is in RB.1 with a value of 255 being about five
          ; seconds with a 4 MHz clock rate.
          ;
          ; The routine has also been folded into itself so that the return
          ; point is just before the entry point to facilitate calling by SEP
          ; by causing the entry point to be reset automaticaly each call.


          ; If greater than 64, then 1.5 bit times is more than 8 bits so we
          ; can't simply use the normal delay loop which has an 8-bit counter.
          ; So we do the half bit first then fall into a normal one-bit delay.

bitcomp:    ghi   re                    ; get half of bit time delay
            shr

bithalf:    smi   4                     ; delay in increments of 4 cycles
            bdf   bithalf

            adi   bitfrac+1             ; calculate jump from remainder
            plo   r3

            skp                         ; delay for between 2-5 cycles
            skp
            lskp
bitfrac:    ldi   0

          ; Delay for a full bit time using decompressed value from stack.

bitloop:    ghi   re                   ; get delay time

bittime:    smi   4                    ; delay in increments of 4 cycles
            bdf   bittime

            adi   bitjump+1            ; calculate jump from remainder
            plo   r3

            skp                        ; delay for between 2-5 cycles
            skp
            lskp
bitjump:    ldi   0

            BRSP  bitspac               ; if space then shift in a zero bit

            glo   re                    ; data is mark so shift in a one bit
            shrc
            br    bitnext

bitspac:    glo   re                    ; data is space so shift in a zero
            shr
            plo   re

bitnext:    plo   re                    ; more bits to read if byte not zero
            bdf   bitloop

bitstop:    BRSP  bitstop               ; wait until the stop bit starts

bitretn:    sep   sret                  ; return with pc pointing to start

          ; This is the entry point of the bit-bang UART receive routine. The
          ; first thing to do is watch for a start bit, but we need to have a
          ; time limit of how long to wait. Since we need to maintain high
          ; timing resolution, we check for the start bit change every-other
          ; instruction interleaved into the timing loop.

tmobits:    BRSP  bitinit               ; save timeout value
            phi   rb

            BRSP  bitinit               ; loop within the loop to add time
bitidle:    ldi   4

bitdlay:    BRSP  bitinit               ; decrement loop counter in d
            smi   1

            BRSP  bitinit               ; loop until delay finished
            bnz   bitdlay

            BRSP  bitinit               ; decrement main timer loop counter
            dec   rb

            BRSP  bitinit               ; check the high byte for zero
            ghi   rb

            BRSP  bitinit               ; if zero, then we have timed out
            bz    bitretn

            BRMK  bitidle               ; continue until something happens

          ; The same shift register that is used to receive bits into is also
          ; used to count loops by preloading it with all ones except the last
          ; bit, which will shift out as zero when all the register is full.

bitinit:    ldi   %01111111              ; set stop bit into byte buffer
            plo   re

            br    bitcomp                ; enter regular bit delay routine


          ; ------------------------------------------------------------------
          ; This is the transmit routine of the Nitro soft UART. This returns
          ; following setting the level of the stop bit to maximize time for
          ; processing, especially to receive a following character from the
          ; other end. To avoid stop bit violations, we therefore need to 
          ; delay on entry just a little less than a bit time.

putbits:    plo   re                    ; save byte to send to shift register

            ghi   re
bitwait:    smi   4                     ; wait for minimum stop bit time
            bdf   bitwait

          ; Once the stop bit is timed, send the start bit and delay, and end
          ; the delay with DF set as we then jump into the send loop and this
          ; level will get shifted into the shift register just before we exit
          ; and so determines the stop bit level.

            SESP                        ; set start bit level

            ghi   re                    ; get bit time, do again as a no-op
            ghi   re

bitstrt:    smi   4                     ; delay 4 cycles for each 4 counts
            bdf   bitstrt

            adi   bitsetf+1             ; jump into table for fine delay
            plo   r3

          ; For each bit we time the bulk delay with a loop and then jump into
          ; a specially-constructed table to create the fine delay to a single
          ; machine cycle. This is where we loop back for each bit to do this.
          ; Exit from the delay with DF clear as this will get shifted into
          ; the shift register, when it is all zeros that marks the end.

bitmore:    ghi   re                    ; get bit time factor

bitbits:    smi   4                     ; delay 4 cycles for each 4 counts
            bdf   bitbits

            sdi   bitclrf-1             ; jump into table for fine delay
            plo   r3

bitclrf:    skp                         ; delays from here are 5,4,3,2 cycles
            skp
            lskp
bitsetf:    ldi   0

            glo   re                    ; shift count bit in, data bit out
            shrc
            plo   re

            bdf   bitmark               ; if bit is one then that's a mark

            SESP                        ; else set space output, next bit
            br    bitmore

bitmark:    SEMK                        ; set mark output, do next bit
            bnz   bitmore

          ; When the shift register is all zeros, we have sent 8 data bits and
          ; set the stop bit level. Return through the SEP in GETBITS so that
          ; the PC is reset to receive a byte each time after sending one.

            br    bitretn               ; return through getbits to set pc


getbits:    BRSP  bitinit               ; save timeout value
            br    getbits


          ; The data buffer needs to be page aligned to simplify the pointer
          ; math so go ahead and align both of these here. Neither is 
          ; included in the executable though since they are 'ds'.

            org   (($-1)|255)+1

buffer:     ds    128                   ; xmodem data receive buffer

end:        end   begin

