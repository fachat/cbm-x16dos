;-----------------------------------------------------------------------------
; spi.s
; Copyright (C) 2023 Andre Fachat
;
; Using the interface described here
; https://github.com/fachat/MicroPET/blob/main/CPLD/SPI.md
;-----------------------------------------------------------------------------

	.include "spi.inc"

	.import sector_buffer

	.export spi_ctrl, spi_read, spi_write, spi_select, spi_deselect, spi_read_sector, spi_write_sector



;-----------------------------------------------------------------------------
; Registers
;-----------------------------------------------------------------------------
SPI_CTRL      = $e808
SPI_DATA      = $e809
SPI_PEEK      = $e80a

SPI_CTRL_SELECT_MASK	= %00000111
SPI_CTRL_SELECT_SDCARD	= 3

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
	and #(SPI_CTRL_SELECT_MASK ^ $FF)
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
spi_rw:
	sta SPI_DATA	; 4
@1:	bit SPI_CTRL	; 4
	bmi @1		; 2 + 1 if branch
	lda SPI_PEEK	; 4
	rts		; 6
			; >= 22 cycles

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

;-----------------------------------------------------------------------------
; sdcard_init
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
spi_ctrl:
	; No-Op for now
	;sta SPI_CTRL
	rts


;-----------------------------------------------------------------------------
; spi_read_sector
; read 512 bytes from SPI to sector_buffer
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
spi_read_sector:

	; Read 512 bytes of sector data
        ldy #0

@1:	jsr spi_read
	sta sector_buffer + 0, y
	iny
	bne @1

@2:	jsr spi_read
	sta sector_buffer + 256,y
	iny
	bne @2

	jsr spi_read		; first CRC byte
        jmp spi_read		; second CRC byte

;-----------------------------------------------------------------------------
; spi_write_sector
; write 512 bytes of data from sector_buffer
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
spi_write_sector:

        ; Send 512 bytes of sector data
        ldy #0

@1:     lda sector_buffer, y            ; 4
        sta SPI_DATA
@3:	bit SPI_CTRL
	bmi @3
        iny                             ; 2
        bne @1                          ; 2 + 1

        ; Y already 0 at this point
@2:     lda sector_buffer + 256, y      ; 4
	sta SPI_DATA
@4:	bit SPI_CTRL
	bmi @4
        iny                             ; 2
        bne @2                          ; 2 + 1

        rts

