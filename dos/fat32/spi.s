;-----------------------------------------------------------------------------
; spi.s
; Copyright (C) 2020 Frank van den Hoef
;-----------------------------------------------------------------------------

	.include "lib.inc"

	.export spi_ctrl, spi_read, spi_write, spi_select, spi_deselect

;-----------------------------------------------------------------------------
; deselect card
;
; clobbers: A
;-----------------------------------------------------------------------------
spi_deselect:
	lda SPI_CTRL
	and #(SPI_CTRL_SELECT_MASK ^ $FF)
	sta SPI_CTRL

	jmp spi_read

;-----------------------------------------------------------------------------
; select card
;
; clobbers: A,X,Y
;-----------------------------------------------------------------------------
spi_select:
	lda SPI_CTRL
	ora #SPI_CTRL_SELECT_SDCARD
	sta SPI_CTRL

	jmp spi_read

;-----------------------------------------------------------------------------
; spi_read
;
; result in A
;-----------------------------------------------------------------------------
spi_read:
	lda #$FF	; 2
	sta SPI_DATA	; 4
@1:	bit SPI_CTRL	; 4
	bmi @1		; 2 + 1 if branch
	lda SPI_DATA	; 4
	rts		; 6
			; >= 22 cycles


;.macro spi_read_macro
;	.local @1
;	lda #$FF	; 2
;	sta SPI_DATA	; 4
;@1:	bit SPI_CTRL	; 4
;	bmi l1		; 2 + 1 if branch
;	lda SPI_DATA	; 4
;.endmacro

;-----------------------------------------------------------------------------
; spi_write
;
; byte to write in A
;-----------------------------------------------------------------------------
spi_write:
	sta SPI_DATA
@1:	bit SPI_CTRL
	bmi @1
	rts

;.macro spi_write_macro
;	.local @1
;	sta SPI_DATA
;@1:	bit SPI_CTRL
;	bmi @1
;.endmacro

;-----------------------------------------------------------------------------
; sdcard_init
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
spi_ctrl:
	sta SPI_CTRL
	rts


