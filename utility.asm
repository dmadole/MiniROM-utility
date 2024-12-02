;  Copyright 2022, David S. Madole <david@madole.net>
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


; ra   - input character routine
; rb   - output character routine
; rc   - message output routine
;
; re.0 - input timeout
; re.1 - soft uart baud rate

#define VERSION          4.7.4

#define NO_GROUP         0       ; defined by hardware, do not change
#define UART_DETECT              ;  Use 1854 if no EF serial cable present

#ifdef 1802MINI
  #define BRMK           bn2     ; These can be anything on the 1802/Mini but
  #define BRSP           b2      ;  conventionally they are the same as on the
  #define SESP           req     ;  Pico/Elf using EF2 for serial input and
  #define SEMK           seq     ;  Q for serrial output, both inverted
  #define SET_BAUD       19200   ; Use this on bit-bang instead of auto-baud
  #define FREQ_KHZ       4000    ; Clock frequency for baud rate calculation
  #define EXP_PORT       5       ;  Group expander port
  #define UART_GROUP     0       ; Group select for 1854
  #define UART_DATA      6       ;  Data port for 1854
  #define UART_STATUS    7       ;  Status/command port for 1854
#endif

#ifdef SUPERELF
  #define BRMK           bn2     ; These can be anything on the 1802/Mini but
  #define BRSP           b2      ;  conventionally they are the same as on the
  #define SESP           req     ;  Pico/Elf using EF2 for serial input and
  #define SEMK           seq     ;  Q for serrial output, both inverted
  #define SET_BAUD       9600    ; Use this on bit-bang instead of auto-baud
  #define FREQ_KHZ       1790    ; Clock frequency for baud rate calculation
  #define EXP_PORT       5      ;  Group expander port
  #define UART_GROUP     0       ; Group select for 1854
  #define UART_DATA      6       ;  Data port for 1854
  #define UART_STATUS    7       ;  Status/command port for 1854
#endif

#ifdef RC1802
  #define BRMK           bn3     ; These can be anything on the 1802/Mini but
  #define BRSP           b3      ;  conventionally they are the same as on the
  #define SESP           req     ;  Pico/Elf using EF2 for serial input and
  #define SEMK           seq     ;  Q for serrial output, both inverted
  #define SET_BAUD       9600    ; Use this on bit-bang instead of auto-baud
  #define FREQ_KHZ       2000    ; Clock frequency for baud rate calculation
  #define EXP_PORT       1       ;  Group expander port
  #define UART_GROUP     1
  #define UART_DATA      2       ;  Data port for 1854
  #define UART_STATUS    3       ;  Status/command port for 1854
#endif


soh:        equ   1
etx:        equ   3
eot:        equ   4
ack:        equ   6
bs:         equ   8
lf:         equ   10
cr:         equ   13
nak:        equ   21
can:        equ   24


            ; All the code gets copied from ROM to RAM and then run from 
            ; there so that EEPROM programming does not cause issues, since
            ; the EEPROM cannot be read while programming is happening.
            ; The code is copied into what would be the kernel space from
            ; 0100 upwards and puts the stack at 00ff downwards.

            org   100h

start:      ldi   0eb00h.1              ; get msb of address to copy from
            phi   r7

            ldi   start.1               ; get msb of address to copy to
            phi   r8

            ldi   start.0               ; lsb of both is the same
            plo   r7
            plo   r8

            ldi   (end-start).1         ; get length of code to copy
            phi   r9
            ldi   (end-start).0
            plo   r9

            br    cpyloop               ; go copy from rom to ram


            ; SEDIT exits by jumping to D013h so arrange a jump there that
            ; will restart the menu from the copy already in RAM.

            org   0113h

            lbr   reenter               ; reentry point for sedit exit


            ; Copy the code from ROM to RAM and then jump to it.

cpyloop:    lda   r7                    ; copy bytes from rom to ram
            str   r8
            inc   r8
            dec   r9
            glo   r9
            bnz   cpyloop
            ghi   r9
            bnz   cpyloop

            ldi   jumpr3.1              ; get address to jump to
            phi   r3
            ldi   jumpr3.0
            plo   r3

            sep   r3                    ; change pc to r3 to jump

jumpr3:     b4    reenter               ; if input pressed, enter menu

            lbr   0f000h                ; else boot

reenter:    ldi   00ffh.1               ; setup stack from 00ff in r2
            phi   r2
            ldi   00ffh.0
            plo   r2

            sex   r2                    ; use r2 for sp

            ldi   message.1             ; pointer to message out routine
            phi   rc
            ldi   message.0
            plo   rc

            ldi   msgeban.1             ; pointer to initial banner
            phi   r7
            ldi   msgeban.0
            plo   r7

            BRMK  bitbang               ; use bit-bang if cable connected

         #ifdef UART_GROUP
            sex   r3
            out   EXP_PORT
            db    UART_GROUP
            sex   r2
         #endif

            inp   UART_DATA             ; clear uart registers and flags
            inp   UART_STATUS

            inp   UART_STATUS           ; does it seem like 1854 present
            ani   2fh
            bnz   bitbang

            ldi   19h                   ; initialize uart data format
            str   r2
            out   UART_STATUS
            dec   r2

            ldi   uread.1               ; set input routine to use uart
            phi   ra
            ldi   uread.0
            plo   ra

            ldi   utype.1               ; set output routine to use uart
            phi   rb
            ldi   utype.0
            plo   rb

            ldi   0
            phi   re

            lbr   insmenu               ; display main installer menu


bitbang:    ldi   input.1               ; use bit-bang uart for input
            phi   ra
            ldi   input.0
            plo   ra

            ldi   output.1              ; use bit-bang uart for output
            phi   rb
            ldi   output.0
            plo   rb

            SEMK                        ; set serial to idle level

            ldi   5                    ; delay for more than one char
            phi   r7
settle:     dec   r7
            ghi   r7
            lbnz  settle

            ldi   (FREQ_KHZ*5)/(SET_BAUD/25)-23
            phi   re

            lbz   insmenu               ; set baud rate constant
            smi   1
            phi   re


            ; Enter the main command loop by displaying the banner message,
            ; or the output from the previous command, and then the menu.

insmenu:    mark                        ; save return x, p on stack
            inc   r2

            ldi   msgimen.1             ; pointer to menu text
            phi   r7
            ldi   msgimen.0
            plo   r7

            sep   rc                    ; display menu
            dec   r2

            ldi   0                     ; disable input timeout
            plo   re


            ; This is an abbreviated input routine that accepts a single
            ; digit 1-5 only but acts like a line input in that it accepts
            ; backspace and needs a return keytroke to proceed.

indigit:    sep   ra                    ; get keystroke
            dec   r2

            sdi   '2'                   ; if greater than 5 try again
            lbnf  indigit

            sdi   '2'-'1'               ; if less than 1 try again
            lbnf  indigit

            plo   r9                    ; store value 0-4 meaning 1-5

            adi   '1'                   ; back into digit and display
            sep   rb
            dec   r2


            ; We have input a menu selection, now just look for a backspace
            ; to undo the digit or a return to accept.

ingetcr:    sep   ra                    ; get keystroke
            dec   r2

            smi   bs                    ; if backspace go do it
            lbz   inbacks

            smi   cr-bs                 ; if not return try again
            lbnz  ingetcr


            ; When return is pressed, output two newline sequences to 
            ; create a blank line, then dispatch based on previous digit
            ; that was entered.

            glo   r9                    ; 1 = boot from rom
            lbz  bootrom 

            ldi   msgeban.1             ; pointer to eeprom utility banner
            phi   r7
            ldi   msgeban.0
            plo   r7

            lbr   eepmenu               ; 2 = eeprom utility


            ; If a backspace received, erase the input digit and go back
            ; to get another digit.

inbacks:    ldi   msgback.1             ; pointer to backspace sequence
            phi   r7
            ldi   msgback.0
            plo   r7

            sep   rc                    ; output and go back to digit input
            dec   r2

            lbr   indigit               ; go back and get new digit


            ; Boot system. Do a full initialization of stack, SCALL, and
            ; console first as this might be called directly.

bootrom:    ldi   21                    ; enough for 300 baud at 10 Mhz

bootdly:    phi   rf
            dec   rf                    ; wait for last transmitted chars
            ghi   rf
            bnz   bootdly

         #ifdef UART_GROUP
            ghi   re
            lbnz  0f003h

            sex   r3
            out   EXP_PORT
            db    NO_GROUP
         #endif

            lbr   0f003h                ; boot system via bios


            ; Enter the main command loop by displaying the banner message,
            ; or the output from the previous command, and then the menu.

eepmenu:    mark                        ; put x, p onto stack for return
            inc   r2

            sep   rc                    ; display message
            dec   r2

            ldi   msgemen.1             ; pointer to menu text
            phi   r7
            ldi   msgemen.0
            plo   r7

            sep   rc                    ; display menu
            dec   r2

            ldi   0                     ; disable input timeout
            plo   re


            ; This is an abbreviated input routine that accepts a single
            ; digit 1-6 only but acts like a line input in that it accepts
            ; backspace and needs a return keytroke to proceed.

eedigit:    sep   ra                    ; get keystroke
            dec   r2

            sdi   '6'                   ; if greater than 6 try again
            lbnf  eedigit

            sdi   '6'-'1'               ; if less than 1 try again
            lbnf  eedigit

            plo   r9                    ; store value 0-5 meaning 1-6

            adi   '1'                   ; back into digit and display
            sep   rb
            dec   r2


            ; We have input a menu selection, now just look for a backspace
            ; to undo the digit or a return to accept.

eegetcr:    sep   ra                    ; get keystroke
            dec   r2

            smi   bs                    ; if backspace go do it
            lbz   eebacks

            smi   cr-bs                 ; if not return try again
            lbnz  eegetcr


            ; When return is pressed, output two newline sequences to 
            ; create a blank line, then dispatch based on previous digit
            ; that was entered.

            glo   r9                    ; 1 = test xmodem
            lbz   test

            smi   1                     ; 2 = unprotect eeprom
            lbz   unprot

            smi   1                     ; 3 = program eeprom
            lbz   program

            smi   1                     ; 4 = verify eeprom
            lbz   verify

            smi   1                     ; 5 = protect eeprom
            lbz   protect

            lbr   reboot


            ; If a backspace received, erase the input digit and go back
            ; to get another digit.

eebacks:    ldi   msgback.1             ; pointer to backspace sequence
            phi   r7
            ldi   msgback.0
            plo   r7

            sep   rc                    ; output and go back to digit input
            dec   r2

            lbr   eedigit               ; go back and get new digit


            ; Reboot the system by jumping to 8000h with X and P set to zero
            ; as if the system was coming out of a hardware reset.
            
reboot:     ldi   80h                   ; load jump address to r0
            phi   r0
            ldi   00h
            plo   r0

            sex   r0                    ; set x and p to zero
            sep   r0


            ; Protect or unprotect the EEPROM by issuing the necessary
            ; sequence of location writes. Either of the two entry points
            ; will be called with D=0 and DF=1; we use DF as the flag for
            ; which operation by clearing it for protect.

protect:    shr                         ; clear df flag

unprot:     ldi   55h+80h               ; first magic address for algorithm
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

            lbdf  isunpro               ; if unprotect, branch here

            ldi   0a0h                  ; 3rd write for protect: a0->5555
            str   r7

            ldi   msgprot.1             ; pointer to protected message
            phi   r7
            ldi   msgprot.0
            plo   r7
            
            lbr   eepmenu               ; output message, return to menu
            

            ; Output the remainder of the write sequence for unprotect.

isunpro:    ldi   080h                  ; 3rd write for unprotect: 80->5555
            str   r7
            
            ldi   0aah                  ; 4th write for unprotect: aa->5555
            str   r7

            ldi   055h                  ; 5th write for unprotect: 55->2aaa
            str   r8

            ldi   020h                  ; 6th write for unprotect: 20->5555
            str   r7

            ldi   msgunpr.1             ; pointer to unprotected message
            phi   r7
            ldi   msgunpr.0
            plo   r7

            lbr   eepmenu               ; output message, return to menu


            ; Test command - display prompt, load function, and run.

test:       ldi   msgtest.1             ; test xmodem prompt pointer
            phi   r7
            ldi   msgtest.0
            plo   r7

            ldi   0                     ; function code for test
            lbr   xmodem


            ; Program command - display prompt, load function, and run.

program:    ldi   msgprog.1             ; program xmodem prompt pointer
            phi   r7
            ldi   msgprog.0
            plo   r7

            ldi   1                     ; function code for program
            lbr   xmodem


            ; Verify command - display prompt, load function, and run.

verify:     ldi   msgverf.1             ; verify xmodem prompt pointer
            phi   r7
            ldi   msgverf.0
            plo   r7

            ldi   2                     ; function code for verify
            lbr   xmodem


            ; Save the function code into R9.1, output the prompt message,
            ; and fall into the main XMODEM routine.

xmodem:     phi   r9                    ; save requested mode

            sep   rc                    ; output prompt passed in r7
            dec   r2


            ; This XMODEM receive code performs the following three functions
            ; around receiving a file based on the selector passed in R9.1:
            ;
            ;   0: Test - this receives a file but does nothing with the
            ;      data received. The purpose is to verify that XMODEM can
            ;      be successfully run before attempting a write operation.
            ;
            ;   1: Program - this receives a file and writes it to the 
            ;      EEPROM a block at a time, and verifies each block after.
            ;
            ;   2: Verify - this receives a file and compares it to the
            ;      existing EEPROM contents.
            ;
            ; Upon success, the same code is returned that was passed in.
            ; On failure, the code n R9.1 is changed to the following:
            ;
            ;   3: Failed - the verification of data failed, either as part
            ;      of a program operation, or as a verify operation.
            ;
            ; Besides the mode passed in R9.1, this uses the following
            ; registers internally:
            ;
            ;   R7:   Pointer to receive buffer
            ;   R8:   Pointer to EEPROM location
            ;   R9.0: Packet number being received
            ;   RF.0: Calculation of checksum
            ;
            ; Note that the buffer needs to be page aligned as a test for 
            ; zero is used to detect a full packet has been received (the
            ; buffer is filled from top down).

            sex   r7                    ; use buffer pointer for index 

            ldi   buffer.1              ; set msb of buffer pointer
            phi   r7

            dec   r2                    ; do a mark to the stack once, keep
            mark                        ;  using it over and over to same time
            inc   r2

            ldi   80h                   ; set r8 to point to start of eeprom
            phi   r8
            ldi   00h
            plo   r8

            ldi   1                     ; start packet sequence at one
            plo   r9

            lbr   flushin               ; branch to packed receive code

            ; The inner part of the XMODEM code is timing sensitive and needs
            ; to use short branch instructions, so it is located in a block
            ; of code that is page aligned. Think of it as being here.

havepkt:    sdi   0                     ; negate the checksum returned
            plo   rf

            ldi   128                   ; reset receive buffer to start
            plo   r7

calcsum:    glo   rf                    ; add each byte to the checksum
            add 
            plo   rf

            dec   r7                    ; repeat until at end of buffer
            glo   r7
            lbnz  calcsum

            glo   rf                    ; if result not zero, then nak
            lbnz  sendnak


            ; At this point we have received a packet verified to be good.

            ghi   r9                    ; retrieve function code

            smi   1                     ; if 1, program block to EEPROM
            lbz   write

            smi   1                     ; if 2, verify block against EEPROM
            lbz   check


            ; If neither a program nor verify operation, including if we
            ; have failed to verify a block, fall through and process the
            ; block without doing anything with the data.

nextpkt:    ldi   128                   ; reset buffer pointer to start
            plo   r7

            glo   r9                    ; increate packet sequence counter
            adi   1
            plo   r9

            ldi   ack                   ; send an ack and get next packet
            lbr   sendack


            ; If an EEPROM program operation, then write this packet
            ; to EEPROM in block mode (which will take two EEPROM blocks
            ; per XMODEM packet). Fall through to verify each packet.

write:      ldi   128                   ; reset buffer pointer to start
            plo   r7

            sex   r8                    ; verify against eeprom data

wrtloop:    ldn   r7                    ; program byte to eeprom
            str   r8

            glo   r8                    ; if not the end of a block, then
            ani   63                    ;  skip ahead to write next byte
            xri   63
            lbnz  noblock

wrtwait:    ldn   r8                    ; wait until bit 6 of consecutive
            xor                         ;  reads from the eeprom are the same
            ani   40h
            lbnz  wrtwait

noblock:    inc   r8                    ; advance source and target pointers
            dec   r7

            glo   r7                    ; if not end of packet, continue
            lbnz  wrtloop

            sex   r7                    ; back to pointing to buffer

            glo   r8                    ; set eeprom address back to start
            smi   128                   ;  of block, fall through to verify
            plo   r8
            ghi   r8
            smbi  0
            phi   r8


            ; Verify packet against EEPROM contents, if failure, then set
            ; the failure mode code into R9.1 but keep going. We can't
            ; interrupt the XMODEM file receive even if there's an error.

check:      ldi   128                   ; set buffer pointer to start
            plo   r7
            
chkloop:    ldn   r8                    ; if byte matches, go on to next
            xor
            lbz   chkgood

            ldi   3                     ; if mismatch, set failure code
            phi   r9
            
chkgood:    dec   r7                    ; advance source and target pointers
            inc   r8
            
            glo   r7                    ; loop until all packet checked
            lbnz  chkloop

            lbr   nextpkt               ; continue to next packet


            ; If transfer was cancelled, send an ACK and then display
            ; cancelled message and return to menu.

cancel:     ldi   ack                   ; send ack to cancel command
            sep   rb

            ldi   msgcanc.1             ; get pointer to cancelled message
            phi   r7
            ldi   msgcanc.0
            plo   r7

            lbr   eepmenu               ; display message, return to menu


            ; At end of file, see if there was an error and display the
            ; appropriate message, then return to the menu.

endfile:    ldi   ack                   ; send ack to end-of-file command
            sep   rb

            ghi   r9                    ; if code is still 1 or 2, success
            smi   3
            lbnf  success

            ldi   msgfail.1             ; get pointer to failure message
            phi   r7
            ldi   msgfail.0
            plo   r7

            lbr   eepmenu               ; display message, return to menu
            
success:    ldi   msggood.1             ; get pointer to success message
            phi   r7
            ldi   msggood.0
            plo   r7

            lbr   eepmenu               ; display message, return to menu




uinput:     inp    UART_DATA

upopret:    inc    r2
            ret

uread:      sex    r2
            dec    r2

uwait:      inp    UART_STATUS
            shr
            lbdf   uinput

            glo    re
            lbz    uwait

            phi    rf
            ldi    255
            plo    rf

udelay1:    ldi    170
            plo    re

udelay2:    inp    UART_STATUS
            shr
            lbdf   uinput

            dec    re
            glo    re
            lbnz   udelay2

            dec    rf
            ghi    rf
            lbnz   udelay1

            lbr    upopret



ureturn:    ret

utype:      sex   r2
            dec   r2
            stxd
           
uisbusy:    inp   UART_STATUS
            shl
            lbnf  uisbusy

            inc   r2
            out   UART_DATA

            lbr   ureturn


; ---------------------------------------------------------------------------
; message
;
; output a message from memory up to but not including a terminating null.
;
; entry                      ;
;   r7   - points to message to output
;   re.1 - baud rate constant
;
; exit:
;   d    - set to zero
;   r7   - left pointing to the terminating null
;   rf.0 - modified

msgret:     inc   r2
            sex   r2
            ret

message:    dec   r2
            mark
            inc   r2

mesglp:     lda   r7
            lbz   msgret
            
            sep   rb
            dec   r2

            lbr   mesglp



msgimen:    db    cr,lf,cr,lf
            db    "Mini/ROM Utility V.VERSION",cr,lf

            db    cr,lf
            db    "1. Boot from ROM",cr,lf
            db    "2. EEPROM Utility",cr,lf
            db   cr,lf
            db    "   Option ? ",0

msgeban:    db   cr,lf,cr,lf,0

msgemen:    db   cr,lf
            db   "1. Test XMODEM",cr,lf
            db   "2. Unprotect EEPROM",cr,lf
            db   "3. Program EEPROM",cr,lf
            db   "4. Verify EEPROM",cr,lf
            db   "5. Protect EEPROM",cr,lf
            db   "6. Restart",cr,lf
            db   cr,lf
            db   "   Option ? ",0

msgunpr:    db   cr,lf,cr,lf,"EEPROM Write Enabled!",cr,lf,0
msgprot:    db   cr,lf,cr,lf,"EEPROM Write Protected!",cr,lf,0
msgtest:    db   cr,lf,cr,lf,"Send XMODEM to Test... ",0
msgprog:    db   cr,lf,cr,lf,"Send XMODEM to Program... ",0
msgverf:    db   cr,lf,cr,lf,"Send XMODEM to Verify... ",0
msggood:    db   "Success!",cr,lf,0
msgfail:    db   "Failure!",cr,lf,0
msgcanc:    db   "Cancelled!",cr,lf,0

msgback:    db   bs,' ',bs,0
msgline:    db   cr,lf,cr,lf,0

            org  (0ffh + $) & 0ff00h

; ---------------------------------------------------------------------------
; input
;
; receive a byte from the soft uart optionally with a timeout in case no
; character is received. to receive back-to-back bytes continuously at the
; maximum baud rate, you need to call this again no more than 18 machine
; cycles after it returns, including the sep instruction itself.
;
; entry:
;   re.0 - timeout delay (0 to disable)
;   re.1 - baud rate constant
;
; exit:
;   on success, d is byte and df is set
;   on timeout, d is zero and df is cleared
;
;   rf.0 - modified (copy of byte if success)
;   rf.1 - modified


inpspc:     smi   0                     ; sets df for one bit, clear for zero

inpmrk:     glo   rf                    ; get current received value and shift
            shrc                        ;  right, shifting new bit in as the 
            plo   rf                    ;  next higher bit. when all initial
            bnf   inpdly                ;  zeros are shifted out, we are done

inpwai:     BRSP  inpwai                ; if last bit was mark then wait

inpret:     sex   r2
            ret

; entry point here

input:      BRSP  inpbeg
            glo   re
            
inpinf:     BRSP  inpbeg
            bz    inpinf

            BRSP  inpbeg
            phi   rf

            BRSP  inpbeg
            ldi   255

            BRSP  inpbeg
            plo   rf

inprst:     BRSP  inpbeg
            ldi   255

inptim:     BRSP  inpbeg
            smi   1

            BRSP  inpbeg
            bdf   inptim

            BRSP  inpbeg
            dec   rf

            BRSP  inpbeg
            ghi   rf

            BRSP  inpbeg
            bnz   inprst

            br    inpret

inpbeg:     ldi   80h                       ; initial register value, we will
            plo   rf                        ;  shift right until 1 shifts out

inpskp:     ghi   re                        ; get delay per bit and divide by
            shr                             ;  two to get to middle of the bit

inplp1:     smi   4                         ; delays for cycles equal to next
            bdf   inplp1                    ;  multiple of 4 of the value of d

            sdi   (inpjp1-1).0              ; above will leave -1 to -4 in d
            plo   ra                        ;  which is the remainder of the
inpjp1:     skp                             ;  machine cycles we need to delay
            skp                             ;  then delays for 6 to 9 cycles
            lskp                            ;  for values of -4 to -1
            ldi   0                         ;  last instr is just 2 cycles

inpdly:     ghi   re

inplp2:     smi   4                         ; delays for cycles equal to next
            bdf   inplp2                    ;  multiple of 4 of the value of d

            sdi   (inpjp2-1).0              ; above will leave -1 to -4 in d
            plo   ra                        ;  which is the remainder of the
inpjp2:     skp                             ;  machine cycles we need to delay
            skp                             ;  then delays for 6 to 9 cycles
            lskp                            ;  for values of -4 to -1
            ldi   0                         ;  last instr is just 2 cycles

            BRMK  inpspc                    ; if not ef2 then space, go set df,
            br    inpmrk                    ;  otherwise mark, leave df clear


; ---------------------------------------------------------------------------
; output
;
; transmit a byte through the soft uart. note that this delays for one bit
; time upon entry so that it can be called back to back without causing stop
; bit violations. this is done at entry rather than exit so that input can
; be called immediately after output without missing the start of a byte
; incoming in response to what was transmitted.
;
; entry:
;   d    - byte to send
;   re.1 - baud rate constant
;
; exit:
;   rf.0 - modified


outstp:     SEMK
            ret

output:     sex   r2

            plo   rf
            
            ghi   re
outdl1:     smi   4
            bdf   outdl1                    ; 4,8,12,16

            sdi   (outjp1-1).0
            smi   0                         ; set df
            plo   rb

outjp1:     skp
            skp
            lskp
            ldi   0                         ; 6,7,8,9

            ghi   re
            SESP
            
outdl2:     smi   4
            bdf   outdl2                    ; 4,8,12,16

            sdi   (outjp2-1).0
            smi   0                         ; set df
            plo   rb

outjp2:     skp
            skp
            lskp
            ldi   0                         ; 6,7,8,9

            glo   rf
            shrc
            plo   rf

            bz    outstp
            bdf   outseq

            SESP

            ghi   re
outdl3:     smi   4
            bdf   outdl3                    ; 4,8,12,16

            sdi   (outjp2-1).0              ; always clears df
            plo   rb

outseq:     SEMK

            ghi   re
outdl4:     smi   4
            bdf   outdl4                    ; 4,8,12,16

            sdi   (outjp2-1).0              ; always clears df
            plo   rb















flushin:    ldi   1                     ; short timeout
            plo   re

            sep   ra
            dec   r2

            bdf   flushin

sendnak:    ldi   5                     ; timeout value
            plo   re

            ldi   128
            plo   r7

            ldi   nak
            
sendack:    sep   rb
            dec   r2
            
            sep   ra                     ; get packet
            dec   r2                     ; repoint to values from mark

            bnf   sendnak

            xri   soh
            bz    recvpkt

            xri   eot ^ soh
            lbz   endfile
            
            xri   can ^ eot
            lbz   cancel
            
            xri   etx ^ can
            lbz   cancel

            br    flushin
            
recvpkt:    sep   ra                     ; get packet
            dec   r2                     ; repoint to values from mark

            str   r7
            out   4
            dec   r7

            str   r7
            glo   r9
            xor
            bnz   flushin

            sep   ra
            dec   r2

            xri   0ffh
            xor
            bnz   flushin

            ldi   128
            plo   r7
            
pktloop:    sep   ra
            dec   r2
            bnf   sendnak               ; timeout

            stxd

            glo   r7
            bnz   pktloop

            sep   ra
            dec   r2
            bnf   sendnak               ; timeout

            lbr   havepkt


            ; The buffer needs to start at a page boundary as XMODEM fills
            ; it frm the top down and relies on the low byte hitting zero
            ; to count the packet input bytes. So put it at the start of
            ; the next page after all the code.

buffer:     equ   (($ + 0ffh) & 0ff00h)


end:        ; thats all folks!

