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


            org 0e800h

          ; Utility is called almost immediately after system reset and so 
          ; normally everything is uninitialized and we need to setup a
          ; stack and change the program counter to r3 to be conventional.
           
initial:    b4    withef4
            lbr   0f000h

withef4:    ldi   end.1
            phi   rd
            ldi   end.0
            plo   rd

            ldi   300h.1
            phi   r2
            phi   r9
            ldi   300h.0
            plo   r2
            plo   r9

            dec   r2
            sex   r2


          ; The decompression algorithm is that from Einar Saukas's standard
          ; Z80 ZX1 decompressor, but is completely rewriten due to how very
          ; different the 1802 instruction set and architecture is.
          ;
          ; R9   - Destination pointer
          ; RA   - Last offset
          ; RB   - Copy offset
          ; RC   - Block length
          ; RD   - Source pointer
          ; RE.0 - Single bit buffer
          ; RE.1 - Return address

decompr:    ldi   -1                    ; last offset defaults to one
            phi   rb
            plo   rb

            ldi   80h                   ; prime the pump for elias
            plo   re


          ; The first block in a stream is always a literal block so the type
          ; bit is not even sent, and we can jump in right at that point.

literal:    glo   r0                    ; get literal block length
            br    elias

copylit:    lda   rd                    ; copy byte from input stream
            str   r9
            inc   r9

            dec   rc                    ; loop until all bytes copied
            glo   rc
            bnz   copylit
            ghi   rc
            bnz   copylit


          ; After a literal block must be a copy block and the next bit
          ; indicates if is is from a new offset or the same offset as last.

            glo   re                    ; get next bit, see if new offset
            shl
            plo   re
            bdf   newoffs


          ; Next block is from the same offset as last block.

            glo   r0                    ; get same offset block length
            br    elias

copyblk:    glo   rb                    ; offset plus position is source
            str   r2
            glo   r9
            add
            plo   ra
            ghi   rb
            str   r2
            ghi   r9
            adc
            phi   ra

copyoff:    lda   ra                     ; copy byte from source
            str   r9
            inc   r9

            dec   rc                     ; repeat for all bytes
            glo   rc
            bnz   copyoff
            ghi   rc
            bnz   copyoff


          ; After a copy from same offset, the next block must be either a
          ; literal or a copy from new offset, the next bit indicates which.

            glo   re                     ; check if literal next
            shl
            plo   re
            bnf   literal


          ; Next block is to be coped from a new offset value.

newoffs:    ldi   -1                     ; msb for one-byte offset
            phi   rb

            lda   rd                     ; get lsb of offset, drop low bit
            shrc                         ;  while setting highest bit to 1
            plo   rb

            bnf   msbskip                ; if offset is only one byte

            lda   rd                     ; get msb of offset, drop low bit
            shrc                         ;  while seting highest bit to 1
            phi   rb

            glo   rb                     ; replace lowest bit from msb into
            shlc                         ;  the lowest bit of lsb
            plo   rb

            ghi   rb                     ; high byte is offset by one
            adi   1
            phi   rb

            bz    endfile                ; if not end of file marker

msbskip:    glo   r0                     ; get length of block
            br    elias

            inc   rc                     ; new offset is one less

            br    copyblk                ; do the copy

endfile:    lbr   300h


          ; Subroutine to read an interlaced Elias gamma coded number from
          ; the bit input stream. This keeps a one-byte buffer in RE.0 and
          ; reads from the input pointed to by RF as needed, returning the
          ; resulting decoded number in RC.

elias:      adi   2
            phi   re

            ldi   1                     ; set start value at one
            plo   rc
            shr

eliloop:    phi   rc                    ; save result msb of value

            glo   re                    ; get control bit from buffer
            shl

            bnz   eliskip               ; if buffer is not empty

            lda   rd                    ; else get another byte
            shlc

eliskip:    bnf   elidone               ; if bit is zero then end

            shl                         ; get a data bit from buffer
            plo   re

            glo   rc                    ; shift data bit into result
            shlc
            plo   rc
            ghi   rc
            shlc

            br    eliloop               ; repeat until done

elidone:    plo   re                    ; save back to buffer

            ghi   re                    ; return
            plo   r0


end:        end   start

