$MODLP51RC2

org 0000H
   ljmp MainProgram
   
CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))

; These register definitions needed by 'math32.inc'
DSEG at 30H
	Result: ds 2
	x: 		ds 4
	y: 		ds 4
	bcd: 	ds 4

BSEG
	mf: 	dbit 1

$NOLIST
$include(math32.inc)
$LIST

; These 'equ' must match the hardware wiring
	LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
	LCD_E  	equ P3.3
	LCD_D4 	equ P3.4
	LCD_D5 	equ P3.5
	LCD_D6 	equ P3.6
	LCD_D7 	equ P3.7
	
$NOLIST
$include(LCD_4bit.inc)
$LIST

CSEG

CE_ADC    EQU  P2.0
MY_MOSI   EQU  P2.1 
MY_MISO   EQU  P2.2
MY_SCLK   EQU  P2.3

INI_SPI:
	setb MY_MISO ; Make MISO an input pin
	clr MY_SCLK           ; Mode 0,0 default
	ret
	
DO_SPI_G:
	mov R1, #0 ; Received byte stored in R1
	mov R2, #8            ; Loop counter (8-bits)
	
DO_SPI_G_LOOP:
	mov a, R0             ; Byte to write is in R0
	rlc a                 ; Carry flag has bit to write
	mov R0, a
	mov MY_MOSI, c
	setb MY_SCLK          ; Transmit
	mov c, MY_MISO        ; Read received bit
	mov a, R1             ; Save received bit in R1
	rlc a
	mov R1, a
	clr MY_SCLK
	djnz R2, DO_SPI_G_LOOP
	ret

; Configure the serial port and baud rate
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    
    ; Now we can proceed with the configuration
	orl PCON ,#0x80
	mov SCON, #0x52
	mov BDRCON, #0x00
	mov BRL, #BRG_VAL
	mov BDRCON, #0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
    ret
    
; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret
    
; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
    
SendStringDone:
    ret
    
Left_blank mac
	mov a, %0
	anl a, #0xf0
	swap a
	jz Left_blank_%M_a
	ljmp %1
	
Left_blank_%M_a:
	Display_char(#' ')
	mov a, %0
	anl a, #0x0f
	jz Left_blank_%M_b
	ljmp %1
	
Left_blank_%M_b:
	Display_char(#' ')
	
endmac

; Sends 10-digit BCD number in bcd to the LCD
Display_10_digit_BCD:
	Set_Cursor(2, 7)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	; Replace all the zeros to the left with blanks
	Set_Cursor(2, 7)
	Left_blank(bcd+4, skip_blank)
	Left_blank(bcd+3, skip_blank)
	Left_blank(bcd+2, skip_blank)
	Left_blank(bcd+1, skip_blank)
	mov a, bcd+0
	anl a, #0f0h
	swap a
	jnz skip_blank
	Display_char(#' ')

skip_blank:
	ret

; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	Set_Cursor(2, 7)
	Display_char(#' ')
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret
	
wait_for_P4_5:
	jb P4.5, $ ; loop while the button is not pressed
	Wait_Milli_Seconds(#50) ; debounce time
	jb P4.5, wait_for_P4_5 ; it was a bounce, try again
	jnb P4.5, $ ; loop while the button is pressed
	ret
	
Temp_flavour_text:  db 'Current Temp:', 0

MyProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#Temp_flavour_text)

Send_BCD mac
	push ar0
	mov r0, %0
	lcall ?Send_BCD
	pop ar0
	endmac

?Send_BCD:
	push acc
	; Send most significant digit
	mov a, r0
	swap a
	anl a, #0fh
	orl a, #30h
	lcall putchar
	; Send least significant digit
	mov a, r0
	anl a, #0fh
	orl a, #30h
	lcall putchar
	pop acc
	ret
	
; Copy the 10-bits of the ADC conversion into the 32-bits of 'x'
convert:
	mov x+0, result+0
	mov x+1, result+1
	mov x+2, #0
	mov x+3, #0
	
	; Multiply by 410
	load_Y(410)
	lcall mul32
	
	; Divide result by 1023
	load_Y(1023)
	lcall div32
	
	; Subtract 273 from result
	load_Y(273)
	lcall sub32
	sjmp convert2
	
	; The 4-bytes of x have the temperature in binary
convert2:
	lcall hex2bcd
	Send_BCD(bcd)
    lcall Display_10_digit_bcd
	ret 
 
MainProgram:
	mov sp, #07FH ; Initialize the stack pointer
	
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#Temp_flavour_text)
    
    lcall InitSerialPort
    lcall SendString

Forever:
	clr CE_ADC
	mov R0, #00000001B 	; Start bit:1
	lcall DO_SPI_G
	
	mov R0, #10000000B 	; Single ended, read channel 0
	lcall DO_SPI_G
	mov a, R1          	; R1 contains bits 8 and 9
	anl a, #00000011B  	; We need only the two least significant bits
	mov Result+1, a    	; Save result high.
	
	mov R0, #55H 		; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov Result, R1     	; R1 contains bits 0 to 7.  Save result low.
	setb CE_ADC
	Wait_Milli_Seconds(#250)
	
	lcall convert
	mov a, #'\r'
    lcall putchar
    mov a, #'\n'
    lcall putchar
	sjmp Forever

END
