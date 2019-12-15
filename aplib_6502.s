; ***************************************************************************
; ***************************************************************************
;
; aplib_6502.s
;
; NMOS 6502 decompressor for data stored in Jorgen Ibsen's aPLib format.
;
; This code is written for the PCEAS/NECASM assembler in HuC & MagicKit.
;
; Copyright John Brandwood 2019.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************



; ***************************************************************************
; ***************************************************************************
;
; Decompression Options & Macros
;

                ;
                ; Assume that we're decompessing from a large multi-bank
                ; compressed data file, and that the next bank may need to
                ; paged in when a page-boundary is crossed.
                ;

APL_FROM_BANK   =       0

                ;
                ; Use a function in zero-page for the copy loop?
                ;
                ; If selected, then apl_initdecomp must be called before
                ; apl_decompress in order to set up the code in zero-page.
                ;
                ; This doesn't really make things much faster in practice
                ; because most copies are small, and the subroutine call
                ; overhead eats up the savings from the faster copy loop.
                ;

APL_ZP_COPY     =       0

                ;
                ; Macro to increment the source pointer to the next page.
                ;

                if      APL_FROM_BANK
APL_INC_PAGE    macro
                jsr     .next_page
                endm
                else
APL_INC_PAGE    macro
                inc     <apl_srcptr + 1
                endm
                endif

                ;
                ; Macro to read a byte from the compressed source data.
                ;

APL_GET_SRC     macro
                lda     [apl_srcptr],y
                inc     <apl_srcptr + 0
                bne     .skip\@
                APL_INC_PAGE
.skip\@:
                endm



; ***************************************************************************
; ***************************************************************************
;
; Data usage is last 11 bytes of zero-page.
;

apl_bitbuf      =       $00F5                   ; 1 byte.
apl_offset      =       $00F6                   ; 1 word.
apl_srcptr      =       $00F8                   ; 1 word.
apl_copy_loop   =       $00FA                   ; 6 bytes.

apl_winptr      =       apl_copy_loop + 1
apl_dstptr      =       apl_copy_loop + 4
apl_length      =       apl_winptr

                ; This 10-byte loop gets copied to zero-page, and overlaps
                ; the bottom 4-bytes of stack memory to use less ZP space.

                if      APL_ZP_COPY

apl_initdecomp: ldy     #$F6                    ; Initialize source index.
.loop:          lda     .loop - $F6,y
                sta     apl_copy_loop - $F6,y
                iny
                bne     .loop
                rts

                endif



; ***************************************************************************
; ***************************************************************************
;
; apl_decompress - Decompress data stored in Jorgen Ibsen's aPLib format.
;
; Args: apl_srcptr = ptr to compessed data
; Args: apl_dstptr = ptr to output buffer
; Uses: lots!
;
; If compiled with APL_FROM_BANK, then apl_srcptr should be within the bank
; window range.
;
; As an optimization, the code to handle window offsets > 64768 bytes has
; been removed, since these don't occur with a 16-bit address range.
;
; As an optimization, the code to handle window offsets > 32000 bytes can
; be commented-out, since these don't occur in typical 8-bit computer usage.
;

apl_decompress: lda     #$80                    ; Initialize an empty
                sta     <apl_bitbuf             ; bit-buffer.

                ldy     #0                      ; Initialize source index.

                ;
                ; 0 bbbbbbbb - One byte from compressed data, i.e. a "literal".
                ;

.literal:       APL_GET_SRC

.write_byte:    ldx     #0                      ; LWM=0.

                sta     [apl_dstptr],y          ; Write the byte directly to
                inc     <apl_dstptr + 0         ; the output.
                bne     .next_tag
                inc     <apl_dstptr + 1

.next_tag:      asl     <apl_bitbuf             ; 0 bbbbbbbb

                if      1
                bne     .skip0
                jsr     .load_bit
.skip0:         bcc     .literal
                else
                bcc     .literal
                bne     .skip1
                jsr     .load_bit
                bcc     .literal
                endif

.skip1:         asl     <apl_bitbuf             ; 1 0 <offset> <length>
                bne     .skip2
                jsr     .load_bit
.skip2:         bcc     .code_pair

                asl     <apl_bitbuf             ; 1 1 0 dddddddn
                bne     .skip3
                jsr     .load_bit
.skip3:         bcc     .copy_two_three

                ; 1 1 1 dddd - Copy 1 byte within 15 bytes (or zero).

.copy_one:      lda     #$10
.nibble_loop:   asl     <apl_bitbuf
                bne     .skip4
                pha
                jsr     .load_bit
                pla
.skip4:         rol     a
                bcc     .nibble_loop
                beq     .write_byte             ; Offset=0 means write zero.

                eor     #$FF                    ; CS from previous ROL.
                adc     <apl_dstptr + 0
                sta     <apl_winptr + 0
                lda     #$FF
                adc     <apl_dstptr + 1
                sta     <apl_winptr + 1

                lda     [apl_winptr],y          ; If must be NZ, or else we'd
                bne     .write_byte             ; have used the other coding.

                ;
                ; 1 1 0 dddddddn - Copy 2 or 3 within 128 bytes.
                ;

.copy_two_three:APL_GET_SRC                     ; 1 1 0 dddddddn
                lsr     a
                beq     .finished               ; Offset 0 == EOF.

                sta     <apl_offset + 0         ; Preserve offset.
                sty     <apl_offset + 1
                tya                             ; Y == 0.
                tax                             ; Bits 8..15 of length.
                adc     #2                      ; Bits 0...7 of length.
                bne     .do_match               ; NZ from previous ADC.

.finished:      rts                             ; All decompressed!

                ;
                ; 1 0 <offset> <length> - gamma-coded LZSS pair.
                ;

.code_pair:     jsr     .get_gamma              ; Bits 8..15 of offset (min 2).

                sty     <apl_length + 1         ; Clear hi-byte of length.

                cpx     #1                      ; CC if LWM==0, CS if LWM==1.
                sbc     #2                      ; -3 if LWM==0, -2 if LWM==1.
                bcs     .normal_pair            ; CC if LWM==0 && offset==2.

                jsr     .get_gamma              ; Get length (A=lo-byte & CC).
                ldx     <apl_length + 1
                bcc     .do_match               ; Use previous Offset.

.normal_pair:   sta     <apl_offset + 1         ; Save bits 8..15 of offset.

                APL_GET_SRC
                sta     <apl_offset + 0         ; Save bits 0...7 of offset.

                jsr     .get_gamma              ; Get length (A=lo-byte & CC).
                ldx     <apl_length + 1

                ldy     <apl_offset + 1         ; If offset <    256.
                beq     .lt256
                cpy     #$7D                    ; If offset >= 32000, length += 2.
                bcs     .match_plus2
                cpy     #$05                    ; If offset >=  1280, length += 1.
                bcs     .match_plus1
                bcc     .do_match
.lt256:         ldy     <apl_offset + 0         ; If offset <    128, length += 2.
                bmi     .do_match

                sec
.match_plus2:   adc     #1                      ; CS, so ADC #2.
                bcs     .match_plus256

.match_plus1:   adc     #0                      ; CS, so ADC #1, or CC if fall
                bcc     .do_match               ; through from .match_plus2.

.match_plus256: inx

.do_match:      eor     #$FF                    ; Negate the lo-byte of length
                tay                             ; and check for zero.
                iny
                beq     .calc_addr
                eor     #$FF

                inx                             ; Increment # of pages to copy.

                clc                             ; Calc destination for partial
                adc     <apl_dstptr + 0         ; page.
                sta     <apl_dstptr + 0
                bcs     .calc_addr
                dec     <apl_dstptr + 1

.calc_addr:     sec                             ; Calc address of match.
                lda     <apl_dstptr + 0
                sbc     <apl_offset + 0
                sta     <apl_winptr + 0
                lda     <apl_dstptr + 1
                sbc     <apl_offset + 1
                sta     <apl_winptr + 1

                if      APL_ZP_COPY
.copy_page:     jsr     apl_copy_loop           ; Execute copy loop in ZP.
                else
.copy_page:     lda     [apl_winptr],y
                sta     [apl_dstptr],y
                iny
                bne     .copy_page
                endif

                inc     <apl_winptr + 1
                inc     <apl_dstptr + 1
                dex                             ; Any full pages left to copy?
                bne     .copy_page

                ldx     #1                      ; LWM=1.
                jmp     .next_tag

                ;
                ; Subroutines for byte & bit handling.
                ;

.load_bit:      APL_GET_SRC                     ; Reload an empty bit-buffer
                rol     a                       ; from the compressed source.
                sta     <apl_bitbuf
                rts

.get_gamma:     lda     #1                      ; Get a gamma-coded value.
.gamma_loop:    asl     <apl_bitbuf
                bne     .skip5
                pha
                jsr     .load_bit
                pla
.skip5:         rol     a
                rol     <apl_length + 1
                asl     <apl_bitbuf
                bne     .skip6
                pha
                jsr     .load_bit
                pla
.skip6:         bcs     .gamma_loop
                rts                             ; Always returns CC.

                if      APL_FROM_BANK
.next_page:     inc     <apl_srcptr + 1         ; Placeholder for a function
                rts                             ; to detect bank overflow.
                endif
