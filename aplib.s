; ***************************************************************************
; ***************************************************************************
;
; aplib.s
;
; HuC6280 decompressor for data stored in Jorgen Ibsen's aPLib format.
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
		; Take 25% loss in speed to make the code smaller?
		; 

APL_BEST_SIZE	=	0

		;
		; Assume that we're decompessing from a large multi-bank
		; compressed data file and that MPR3 (and MPR4) are used
		; as a window into that file?
		;

APL_FROM_MPR3	=	0

		;
		; Macro to increment the source pointer to the next page.
		;

		if	APL_FROM_MPR3
APL_INC_PAGE	macro
		bsr	.next_page
		endm
		else
APL_INC_PAGE	macro
		inc	<apl_srcptr + 1
		endm
		endif

		;
		; Macros to read a byte/bit from the compressed source data.
		;

		if	APL_BEST_SIZE

APL_JMP_TII	=	0
APL_GET_BIT	macro
		bsr	.get_bit
		endm
APL_GET_SRC	macro
		bsr	.get_src
		endm

		else

APL_JMP_TII	=	1
APL_GET_BIT	macro
		asl	<apl_bitbuf
		bne	.skip\@
		bsr	.load_bit
.skip\@:
		endm
APL_GET_SRC	macro
		lda	[apl_srcptr],y
		iny
		bne	.skip\@
		APL_INC_PAGE
.skip\@:
		endm

APL_GET_SRCX	macro
		lda	[apl_srcptr]		; Can be used if you *really*
		inc	<apl_srcptr + 0		; don't want to map MPR4.
		bne	.skip\@
		APL_INC_PAGE
.skip\@:
		endm

		endif



; ***************************************************************************
; ***************************************************************************
;
; Data usage is pretty-much all of the temporary System Card locations.
;
; Note that the TII instruction runs into the bottom 2 bytes of the stack.
;

apl_bitbuf	=	__bp			; 1 byte.

apl_srcptr	=	__si			; 1 word.
apl_offset	=	__di			; 1 word.

apl_winptr	=	__ah			; Part of TII instruction.
apl_dstptr	=	__bh			; Part of TII instruction.
apl_length	=	__ch			; Part of TII instruction.

apl_lwmbit	=	apl_length		; 1 byte.



; ***************************************************************************
; ***************************************************************************
;
; apl_decompress - Decompress data stored in Jorgen Ibsen's aPLib format.
;
; Args: apl_srcptr = ptr to compessed data
; Args: apl_dstptr = ptr to output buffer
; Uses: __bp, __si, __di, __ax, __bx, __cx, __dx
;
; If compiled with APL_FROM_MPR3, then apl_srcptr should be within MPR3, i.e.
; in the range $6000..$7FFF, and both MPR3 & MPR4 should be set.
;
; As an optimization, the code to handle window offsets > 32000 bytes has
; been commented-out, since these don't occur in typical PC Engine usage.
;

apl_decompress:	lda	#$73			; TII instruction.
		sta	<__al

		if	APL_JMP_TII
		tii	.tii_end, __dh, 3	; TII ends with JMP.
		else
		lda	#$60			; TII ends with RTS.
		sta	<__dh			; Saves 6 bytes of code.
		endif

		lda	#$80			; Initialize an empty
		sta	<apl_bitbuf		; bit-buffer.

		cly				; Initialize source index.

		;
		; 0 bbbbbbbb - One byte from compressed data, i.e. a "literal".
		;

.literal:	APL_GET_SRC

.write_byte:	ldx	#-3			; LWM=-3 (C code uses 0).

		sta	[apl_dstptr]		; Write the byte directly to
		inc	<apl_dstptr + 0		; the output.
		bne	.next_tag
		inc	<apl_dstptr + 1

.next_tag:	APL_GET_BIT			; 0 bbbbbbbb
		bcc	.literal

		APL_GET_BIT			; 1 0 <offset> <length>
		bcc	.code_pair

		APL_GET_BIT			; 1 1 0 dddddddn
		bcc	.copy_two_three

                ; 1 1 1 dddd - Copy 1 byte within 15 bytes (or zero).

.copy_one:	lda	#$10
.nibble_loop:	APL_GET_BIT
		rol     a
		bcc	.nibble_loop
		beq	.write_byte		; Offset=0 means write zero.

		eor	#$FF
		adc	<apl_dstptr + 0
		sta	<apl_winptr + 0
		lda	#$FF
		adc	<apl_dstptr + 1
		sta	<apl_winptr + 1

		lda	[apl_winptr]
		bra	.write_byte

		;
		; Subroutines for byte & bit handling.
		;

		if	APL_BEST_SIZE
.get_bit:	asl	<apl_bitbuf		; Get the next bit value from
		beq	.load_bit		; the bit-buffer.
		rts

.get_src:	lda	[apl_srcptr],y		; Get the next byte value from
		iny                             ; from the compressed source.
		beq	.next_page
		rts
		if	APL_FROM_MPR3
		else
.next_page:	inc	<apl_srcptr + 1
		rts
		endif
		endif

		if	APL_FROM_MPR3
.next_page:	inc	<apl_srcptr + 1		; Increment source page, and
		bmi	.next_bank		; check if changed bank.
		rts

.next_bank:	pha				; Increment source bank view
		tma3				; within a large data file.
		inc	a
		tam3
		inc	a
		tam4
		lda	#$60
		sta	<apl_srcptr + 1
		pla
		rts
		endif

.load_bit:	pha				; Reload an empty bit-buffer
		APL_GET_SRC			; from the compressed source.
		rol	a
		sta	<apl_bitbuf
		pla
		rts

.get_gamma:	lda	#1			; Get a gamma-coded value.
		stz	<apl_length + 1
.gamma_loop:	APL_GET_BIT
		rol	a
		rol	<apl_length + 1
		APL_GET_BIT
		bcs	.gamma_loop
		rts

                ;
		; 1 1 0 dddddddn - Copy 2 or 3 within 128 bytes.
                ;

.copy_two_three:APL_GET_SRC			; 1 1 0 dddddddn
		lsr     a
		beq	.finished		; offset 0 == EOF.

		sta	<apl_offset + 0		; Preserve offset.
		stz	<apl_offset + 1
		cla
		adc	#2
		sta	<apl_length + 0
		stz	<apl_length + 1
		bra	.do_match

.finished:	rts				; All decompressed!

                ;
                ; 1 0 <offset> <length> - gamma-coded LZSS pair.
                ;

.code_pair:	bsr	.get_gamma 		; Bits 8..15 of Offset (min 2).

		stx	<apl_lwmbit		; Add LWM (-3 or -2) to Offset.
		adc	<apl_lwmbit
;		tax				; Removing these lines limits
;		lda	<apl_length + 1		; the Offset to < 64768.
;		adc	#$FF
		bcs	.normal_pair		; CC if LWM==-3 && Offset==2.

		bsr	.get_gamma		; Get Length (lo-byte in A).
		bra	.do_match		; Use previous Offset.

.normal_pair:	sta	<apl_offset + 1		; Bits 8..15 of Offset.

		APL_GET_SRC
		sta	<apl_offset + 0		; Bits 0...7 of Offset.

		bsr	.get_gamma		; Get length (lo-byte in A).

		ldx	<apl_offset + 1		; If offset <    256.
		beq	.lt256
;		cpx	#$7D			; If offset >= 32000, length += 2.
;		bcs	.match_plus2
		cpx	#$05			; If offset >=  1280, length += 1.
		bcs	.match_plus1
		bra	.do_match
.lt256:		ldx	<apl_offset + 0		; If offset <    128, length += 2.
		bmi	.do_match

.match_plus2:	inc	a			; Increment length.
		bne	.match_plus1
		inc	<apl_length + 1

.match_plus1:	inc	a			; Increment length.
		bne	.do_match
		inc	<apl_length + 1

.do_match:	sta	<apl_length + 0

		sec				; Calc address of match.
		lda	<apl_dstptr + 0
		sbc	<apl_offset + 0
		sta	<apl_winptr + 0
		lda	<apl_dstptr + 1
		sbc	<apl_offset + 1
		sta	<apl_winptr + 1

		if	APL_JMP_TII
		jmp	__ax
		else
		jsr	__ax
		endif

.match_done:	clc				; Update destination address.
		lda	<apl_length + 0
		adc	<apl_dstptr + 0
		sta	<apl_dstptr + 0
		lda	<apl_length + 1
		adc	<apl_dstptr + 1
		sta	<apl_dstptr + 1

		ldx	#-2			; LWM=-2 (C code uses 1).

		jmp	.next_tag

		if	APL_JMP_TII
.tii_end:	jmp	.match_done
		endif
