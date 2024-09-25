;-----------------------------------------------------------------------------
; sdcard.s
; Copyright (C) 2020 Frank van den Hoef
;-----------------------------------------------------------------------------

;
; TODO: fix according to: http://elm-chan.org/docs/mmc/mmc_e.html
;

	.include "lib.inc"
	.include "sdcard.inc"
	.include "spi.inc"

	.export sector_buffer, sector_buffer_end, sector_lba

	.import spi_ctrl, spi_read, spi_write, spi_select, spi_deselect, spi_read_sector, spi_write_sector

	.bss

sd_card_error_timeout_busy	= $ff

cmd_idx = sdcard_param
cmd_arg = sdcard_param + 1
cmd_crc = sdcard_param + 5

sector_buffer:
	.res 512
sector_buffer_end:

sdcard_param:
	.res 1
sector_lba_x:
	.res 4 ; dword (part of sdcard_param) - LBA of sector to read/write
	.res 1

sector_lba:
	.res 4

is_blk_addr:
	.res 1

timeout_cnt:       .byte 0

	.code

;-----------------------------------------------------------------------------
; wait ready
;
; clobbers: A,X,Y
;-----------------------------------------------------------------------------
wait_ready:
	lda #2
	sta timeout_cnt

@1:	ldx #0		; 2
@2:	ldy #0		; 2
@3:	jsr spi_read	; 22
	cmp #$FF	; 2
	beq @done	; 2 + 1
	dey		; 2
	bne @3		; 2 + 1
	dex		; 2
	bne @2		; 2 + 1
	dec timeout_cnt
	bne @1

	; Total timeout: ~508 ms @ 8MHz

	; Timeout error
	clc
	rts

@done:	sec
	rts


;-----------------------------------------------------------------------------
; send_cmd - Send cmdbuf
;
; first byte of result in A, clobbers: Y
;-----------------------------------------------------------------------------
send_cmd:
	; Select card
	jsr spi_select

	jsr wait_ready
	bcc @error

	; Send the 6 cmdbuf bytes
	lda cmd_idx
	jsr spi_write
	lda cmd_arg + 3
	jsr spi_write
	lda cmd_arg + 2
	jsr spi_write
	lda cmd_arg + 1
	jsr spi_write
	lda cmd_arg + 0
	jsr spi_write
	lda cmd_crc
	jsr spi_write

	; Wait for response
	;ldy #(10 + 1)
	ldy #$30	; sd_cmd_response_retries
@1:	dey
	beq @error	; Out of retries
	jsr spi_read
	bit #$80
	bne @1

	; Success
	sec
	rts

@error:	; Error
	jsr spi_deselect
	clc
	rts

;-----------------------------------------------------------------------------
; send_cmd_inline - send command with specified argument
;-----------------------------------------------------------------------------
.macro send_cmd_inline cmd, arg
	lda #(cmd | $40)
	sta cmd_idx

.if .hibyte(.hiword(arg)) = 0
	stz cmd_arg + 3
.else
	lda #(.hibyte(.hiword(arg)))
	sta cmd_arg + 3
.endif

.if ^arg = 0
	stz cmd_arg + 2
.else
	lda #^arg
	sta cmd_arg + 2
.endif

.if >arg = 0
	stz cmd_arg + 1
.else
	lda #>arg
	sta cmd_arg + 1
.endif

.if <arg = 0
	stz cmd_arg + 0
.else
	lda #<arg
	sta cmd_arg + 0
.endif

.if cmd = 0
	lda #$95
.else
.if cmd = 8
	lda #$87
.else
	lda #1
.endif
.endif
	sta cmd_crc
	jsr send_cmd
.endmacro

;-----------------------------------------------------------------------------
; sdcard_init
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
sdcard_init:
	; Deselect card and set slow speed (< 400kHz)
	lda #SPI_CTRL_SLOWCLK
	jsr spi_ctrl

	; make sure it's deselected
	jsr spi_deselect

	; ---------------------------
	; Generate at least 74 SPI clock cycles with device deselected

	ldx #10
@1:	jsr spi_read
	dex
	bne @1

	; ---------------------------
	; repeatedly send CMD0 

	ldx #$30	; sd_cmd_response_retries
@resend0:
	; Enter idle state
	send_cmd_inline 0, 0
	bcc @error1
	
	cmp #1	; In idle state?
	beq @3

	dex
	bne @resend0

	jmp @error

@3:	; ---------------------------
	; CMD8
	; try to init SDHC - if it fails, fall back to old (SDSC/MMC)

	; SDv2? (SDHC/SDXC)
	send_cmd_inline 8, $1AA
	bcc @error1

	cmp #1	; No error?
	bne @init_sd1_mmc

	; Invalid card (or card not handled yet)

	; screw this
	jsr spi_read
	jsr spi_read

	; is this $01?
	jsr spi_read
	cmp #$01
	bne @error1

	; is this $aa?
	jsr spi_read
	cmp #$aa
	beq @init_sdhc

@error1:
	jmp @error

	;----------------------------
@init_sd1_mmc:
	; SDSC / mmc
	ldx #$30	; repeat count
@sd1_mmc_loop:
	; init card using ACMD41 and parameter $00000000
	send_cmd_inline 55, $00000000
	bcc @error1

	cmp #$01
	bne @init_mmc

	; ------------------
	; CMD41

	send_cmd_inline 41, $00000000
	bcc @error1
	
	cmp #$00
	beq @do58
	
	dex
	bne @sd1_mmc_loop
@error2:
	jmp @error

	;----------------------------
@init_mmc:
	send_cmd_inline 1, $00000000
	bcc @error1
	cmp #$01
	bne @error1
	sec
	rts

	;----------------------------
	; SDHC
	; init card using ACMD41 and parameter $40000000
@init_sdhc:
	ldx #$30	; repeat count
@sdhc_loop:
	send_cmd_inline 55, $00000000
	bcc @error2

	cmp #$01
	bne @init_mmc

	; ------------------
	; CMD41

	send_cmd_inline 41, $40000000
	bcc @error

	cmp #$00
	beq @do58

	dex
	bne @sdhc_loop
	jmp @error

	; ---------------------------
	; CMD58
@do58:
	; Check CCS bit in OCR register
	send_cmd_inline 58, 0
	bcc @error

	jsr spi_read
	pha
	jsr spi_read
	jsr spi_read
	jsr spi_read
	pla
	asl
	sta is_blk_addr
	bpl @is_sdsc

	;and #$40	; Check if this card supports block addressing mode
	;beq @is_sdhc
	

	; ---------------------------
	; CMD16 - set block size to 512 bytes
@cmd16:
	send_cmd_inline 16, $00000200
	bcc @error

@is_sdsc:
	; Select full speed
	jsr spi_deselect
	lda #0
	jsr spi_ctrl

	; Success
	sec
	rts

@error:	jsr spi_deselect

	; Error
	clc
	rts

;-----------------------------------------------------------------------------
; prep cmd_arg from sector_lba
;-----------------------------------------------------------------------------
prep_sector_addr:
	bit is_blk_addr
	bmi @do_blk

	; scale block address to byte address
	; i.e. multiply by $200
	lda sector_lba +2
	pha
	lda sector_lba +1
	pha
	lda sector_lba +0
	asl
	sta cmd_arg +1
	pla
	rol
	sta cmd_arg +2
	pla
	rol
	sta cmd_arg +3
	
	stz cmd_arg +0
	rts

@do_blk:
	lda sector_lba
	sta cmd_arg
	lda sector_lba+1
	sta cmd_arg+1
	lda sector_lba+2
	sta cmd_arg+2
	lda sector_lba+3
	sta cmd_arg+3
	rts

;-----------------------------------------------------------------------------
; sdcard_read_sector
; Set sector_lba prior to calling this function.
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
sdcard_read_sector:
	; Send READ_SINGLE_BLOCK command
	lda #($40 | 17)
	sta cmd_idx
	lda #1
	sta cmd_crc

	jsr prep_sector_addr

	jsr send_cmd
	; Wait for start of data packet
	ldx #0
@1:	ldy #0
@2:	jsr spi_read
	cmp #$FE
	beq @start
	dey
	bne @2
	dex
	bne @1

	; Timeout error
	jsr spi_deselect
	clc
	rts

@start:	jsr spi_read_sector		; fast read of 512 bytes into sector_buffer

	; Success
	jsr spi_deselect
	sec
	rts

;-----------------------------------------------------------------------------
; sdcard_write_sector
; Set sector_lba prior to calling this function.
; result: C=0 -> error, C=1 -> success
;-----------------------------------------------------------------------------
sdcard_write_sector:
	; Send WRITE_BLOCK command
	lda #($40 | 24)
	sta cmd_idx
	lda #1
	sta cmd_crc

	jsr prep_sector_addr

	jsr send_cmd
	cmp #00
	bne @error

	; Wait for card to be ready
	jsr wait_ready
	bcc @error

	; Send start of data token
	lda #$FE
	jsr spi_write

	jsr spi_write_sector

	; Dummy CRC
	lda #0
	jsr spi_write
	jsr spi_write

	; Success
	jsr spi_deselect
	sec
	rts

@error:	; Error
	jsr spi_deselect
	clc
	rts

;-----------------------------------------------------------------------------
; sdcard_check_alive
;
; Check whether the current SD card is still present, or whether it has been
; removed or replaced with a different card.
;
; Out:  c  =1: SD card is alive
;          =0: SD card has been removed, or replaced with a different card
;
; The SEND_STATUS command (CMD13) sends 16 error bits:
;  byte 0: 7  always 0
;          6  parameter error
;          5  address error
;          4  erase sequence error
;          3  com crc error
;          2  illegal command
;          1  erase reset
;          0  in idle state
;  byte 1: 7  out of range | csd overwrite
;          6  erase param
;          5  wp violation
;          4  card ecc failed
;          3  CC error
;          2  error
;          1  wp erase skip | lock/unlock cmd failed
;          0  Card is locked
; Under normal circumstances, all 16 bits should be zero.
; This command is not legal before the SD card has been initialized.
; Tests on several cards have shown that this gets respected in practice;
; the test cards all returned $1F, $FF if sent before CMD0.
; So we use CMD13 to detect whether we are still talking to the same SD
; card, or a new card has been attached.
;-----------------------------------------------------------------------------
sdcard_check_alive:
	; save sector
	ldx #0
@1:	lda sector_lba, x
	pha
	inx
	cpx #4
	bne @1

	send_cmd_inline 13, 0 ; CMD13: SEND_STATUS
	bcc @no ; card did not react -> no card
	tax
	bne @no ; first byte not $00 -> different card
	jsr spi_read
	tax
	bne @no ; second byte not $00 -> different card
	sec
	bra @yes

@no:	clc

@yes:	; restore sector
	; (this code preserves the C flag!)
	ldx #3
@2:	pla
	sta sector_lba, x
	dex
	bpl @2

	php
	jsr spi_deselect
	plp
	rts

;-----------------------------------------------------------------------------
; slowly moving to routines from the Steckschwein that can handle
; more types of SD Cards and is better maintained.

;---------------------------------------------------------------------
; select sd card, pull CS line to low with busy wait
; out:
;   see below
;---------------------------------------------------------------------
;@name: "sd_select_card"
;@out: C, "C = 0 on success, C = 1 on error (timeout)"
;@clobbers: A,X,Y
;@desc: "select sd card, pull CS line to low with busy wait"
sd_select_card:
	jsr spi_select

; fall through to sd_busy_wait
;---------------------------------------------------------------------
; wait while sd card is busy
; C = 0 on success, C = 1 on error (timeout)
;---------------------------------------------------------------------
;@name: "sd_busy_wait"
;@out: C, "C = 0 on success, C = 1 on error (timeout)"
;@clobbers: A,X,Y
;@desc: "wait while sd card is busy"
sd_busy_wait:
      ldx #$ff
@l1:  lda #$ff
      dex
      beq @err

      phx
      jsr spi_read
      plx
      cmp #$ff
      bne @l1
      clc
      rts
@err: lda #sd_card_error_timeout_busy
      sec
      rts



