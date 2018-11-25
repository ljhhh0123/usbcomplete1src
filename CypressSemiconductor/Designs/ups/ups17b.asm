;======================================================================
;		copyright 1997 Cypress Semiconductor Corporation
;======================================================================
; 		USB UPS Reference Firmware
;======================================================================
; Part Number:	CY7C63001
;======================================================================
;
;	This code implements the USB interface for an Uninterruptable
;	Power Supply.  The interface between the CY7C63001 and the UPS
;	is done through RS-232.  The code has been divided into two 
;	portions a general RS-232 part which is in the serial.asm file
;	and the USB UPS part which is in this file.
;
; UPS Features include:
;	5 Reports that are used to represent :
;	- MAIN AC FLOW PHYSICAL COLLECTION
;	- OUTPUT AC FLOW PHYSICAL COLLECTION
;	- BATTERY SYSTEM PHYSICAL COLLECTION
;	- POWER CONVERTER PHYSICAL COLLECTION
;		- AC INPUT PHYSICAL COLLECTION
;		- AC OUTPUT PHYSICAL COLLECTION
;	
;======================================================================
; History:
;	3/3/98	wmh	v1.7	
;	Minor changes and addition of more comments 
;======================================================================
;	12/13/97	wmh	v1.6	
;	All set/get reports added, conversions and strings added
;======================================================================
;	11/24/97	wmh	v0.9	
;	Change in control_read_16 routine to allow program to send more
;	than 255 bytes of the report descriptor
;======================================================================
;	11/4/97	wmh	v0.8	
;	Change in GetReportDescriptor subroutine
;======================================================================
;	10/28/97	wmh	v0.7	
;	Control Send added and get/set report requests added
; 	Control Send is used to send the data of a get report
;======================================================================
;	10/26/97	wmh	v0.6	
;	Control Read 16 added.  This allows for a larger than 256 byte
; 	report descriptor
;======================================================================
;	10/19/97	wmh	v0.4	
;	String Descriptors added (in ROM)
;======================================================================
;	10/16/97	wmh	v0.3	USB Enumeration added
;	Hid Report id 1 is the only report currently supported
;======================================================================
;	9/27/97 :	jb	v0.1
;	Initial code for generic UPS Serial Interface.
;======================================================================
;
;======================== assembler directives ======================== 
;
label:          XPAGEON
;
; USB ports
USB_EP0_TX_Config:      equ     10h     ; USB EP0 transmit configuration
USB_EP1_TX_Config:      equ     11h     ; USB EP1 transmit configuration
USB_Device_Address:     equ     12h     ; USB device address assigned by host
USB_Status_Control:     equ     13h     ; USB status and control register
USB_EP0_RX_Status:      equ     14h     ; USB EP0 receive status

; control ports
Global_Interrupt:	equ 20h 			; Global interrupt enable
Watchdog:		equ 21h 			; Clear watchdog Timer
CExt:			equ 22h 			; Extenal timeout
Timer:		equ 23h 			; free-running Timer
;
; control port
Status_Control:	equ FFh ;
RAMStart:		equ 00h ;
RAMEnd:		equ 80h 			; End of RAM + 1
;**********  Register constants  ************************************
; Processor Status and Control
RunBit:			equ	 1h		; CPU Run bit
SuspendBits:		equ    9h		; Run and suspend bits set
PowerOnReset:		equ   10h		; Power on reset bit
USBReset:			equ	20h		; USB Bus Reset bit
WatchDogReset:		equ	40h		; Watchdog Reset bit

; USB Status and Control
BusActivity:		equ	 1h		; USB bus activity bit

; interrupt masks
TIMER_ONLY:			equ	 4h		; one msec timer
ENUMERATE_MASK:		equ	0Ch		; one msec timer 	
							; USB EP0 interrupt
RUNTIME_MASK:		equ     1Ch     	; one msec timer
							; USB EP0 interrupt
							; USB EP1 interrupt
; USB EP1 transmit configuration
DataToggle:		equ	40h			; Data 0/1 bit

;========================================================================
; constant declarations
;========================================================================
; from USB Spec v1.0 from page 175
;------------------------------------------------------------------------
; standard request codes
get_status:             equ   0
clear_feature:          equ   1
set_feature:            equ   3
set_address:            equ   5
get_descriptor:         equ   6
set_descriptor:         equ   7
get_configuration:      equ   8
set_configuration:      equ   9
get_interface:          equ  10 
set_interface:          equ  11 
synch_frame:            equ  12

; standard descriptor types
device:         	equ  1
configuration:  	equ  2
string:         	equ  3
interface:      	equ  4
endpoint:       	equ  5

; standard feature selectors
endpoint_stalled:       equ  0		; recipient endpoint
device_remote_wakeup:   equ  1		; recipient device
 
;========================================================================
; from HID Class v1.0 Draft #4
;------------------------------------------------------------------------
; class specific descriptor types from section 7.1 Standard Requests
HID:                    equ  21h
report:                 equ  22h
physical:               equ  23h
  
; class specific request codes from section 7.2 Class Specific Requests
get_report:             equ   1
get_idle:               equ   2
get_protocol:           equ   3
set_report:             equ   9
set_idle:               equ  10
set_protocol:           equ  11

;========================================================================
; USB packet constants (debug purposes)
;------------------------------------------------------------------------
;setup:          	equ  B4h
;in:             	equ  96h
;out:            	equ  87h
;data0:          	equ  C3h
;data1:          	equ  D2h
;ack:            	equ  4Bh
;nak:            	equ  5Ah

DISABLE_REMOTE_WAKEUP:  equ   0         ; bit[1] = 0
ENABLE_REMOTE_WAKEUP:   equ   2         ; bit[1] = 1

DISABLE_PROTOCOL:	equ	0			; bit[0] = 0
ENABLE_PROTOCOL:	equ	1			; bit[0] = 1

;========================================================================
; data variable assignments
;========================================================================

; control endpoint 0 fifo
endpoint_0:             equ  70h	; control endpoint

; definitions for SETUP packets
bmRequestType:          equ  70h
bRequest:               equ  71h
wValue:                 equ  72h        ; default wValue (8-bits)
wValueHi:               equ  73h
wIndex:                 equ  74h        ; default wIndex (8-bits)
wIndexHi:               equ  75h
wLength:                equ  76h        ; default wLength (8-bits)
wLengthHi:              equ  77h
 

; interrupt endpoint 1 fifo
endpoint_1:             equ  78h

;*************************************
;
; variable allocations
;*************************************
interrupt_mask:	equ 20h ;
;************************************************
;USB Variables 
;************************************************
endp0_data_toggle: 	equ  21h
loop_counter:		equ  22h
data_start:			equ  23h
data_count:			equ  24h
endpoint_stall:		equ  25h

remote_wakeup_status:   equ  26h        	; remote wakeup request
							; zero is disabled
							; two is enabled
configuration_status:   equ  27h        	; configuration status
							; zero is unconfigured
							; one is configured
;idle_status:           equ  64h        	; support SetIdle and GetIdle
protocol_status:      	equ  65h        	; zero is boot protocol
							; one is report protocol
data_send:			equ  28h		; start of data to be sent
							; next 16 bytes (28-39) are 
							; send buffer
hi_data_count:		equ  60h		; high byte of data count
low_data_count:		equ  61h		; low byte of data count
loop_num:			equ  62h		; loop number (USB sending)
temp2:			equ  63h		; temporary variable
send_ptr:			equ  7Dh		; Send buffer ptr	


;======================================================================
;
;*************** interrupt vector table ****************
; begin execution here after a reset
	org	00h
;
; Interrupt Vector Number 0 : Reset vector
	jmp	Reset
;
; Interrupt Vector Number 1 :  128us interrupt
	jmp	Serial_ISR
	; Used to implement serial receive/transmit
	; bit timing loops.
;
; Interrupt Vector Number 2 :  1024ms interrupt 
	jmp	One_mSec_ISR
	; Used for Watchdog timer.
;
; Interrupt Vector Number 3 :  endpoint 0 interrupt 
	jmp	USB_EP0_ISR  
;
; Interrupt Vector Number 4 :  endpoint 1 interrupt 
	jmp	DoNothing_ISR

;
; Interrupt Vector Number 5 :  reserved interrupt 
	jmp	Reset
	; Runs initialization at reset.
;
; Interrupt Vector Number 6 :  general purpose I/O interrupt 
	jmp	GPIO_ISR
	; Used to detect receive data start bit.
	; Falling edge of Port 0 Bit 7 detected.
;
; Interrupt Vector Number 7 :  Wakeup_ISR or resume interrupt 
	jmp     DoNothing_ISR
	; Not used
;
;************************************************************************
;
ORG  10h
;************************************************************************
; The Cext, and and most GPIO interrupts are not used by the ups
; code.  If any of these interrupts occur, the software should do nothing
; except re-enable the interrupts.
DoNothing_ISR:
	push	A ; save accumulator on stack
	mov	A, [interrupt_mask]
	ipret	Global_Interrupt

;************************************************************************
; The 1 msec interrupt is used to clear the watchdog timer.
; If the watchdog is not cleared for 8 msec, then a watchdog reset will
; occur. 
One_mSec_ISR:
	push	A		; save accumulator on stack
	iowr	Watchdog	; clear watchdog timer
;
; Finish the interrupt handling
	mov	A,[interrupt_mask] ;
	ipret	Global_Interrupt ;
;
;************************************************************************
; The Serial_ISR routine resides in Serial2.asm
;************************************************************************
; The GPIO_ISR routine resides in Serial2.asm
;************************************************************************
	include	"serial.asm"	;

;************************************************************************
; reset processing
; The idea is to put the microcontroller in a known state.  As this
; is the entry point for the "reserved" interrupt vector, we may not
; assume the processor has actually been reset and must write to all
; of the I/O ports. 
Reset:
	mov	A, endpoint_0	; move data stack pointer
	swap	A, dsp		; so it does not write over USB FIFOs 
	mov	A,00h			;
	mov	X,00h			;
ClrRAMLoop:
	swap	A,X			;
	mov	[X+RAMStart],A	;
	inc	X			;
	swap	A,X			;
	cmp	A,RAMEnd		;
	jnz	ClrRAMLoop		;
;
;************************************************************************
; During serial transfers data bit 0 is transmitted first.
; We will use Port 0 Bit 7 for receive and Bit 0 for transmit.
; Data will always be right shifted for either transmit or receive.
; Port 0 Bit 7 will be a falling edge sensitive GPIO_ISR input.
; Port 0 bits 6-0 and Port 1 bits 3-0 will be outputs.
;
	call SerialInitialize	;

;*****************************************
;USB initialization
;*****************************************
	mov A, 0h
	mov [endpoint_stall], A
	mov [remote_wakeup_status], A
	mov [configuration_status], A

	mov A, ENABLE_PROTOCOL
	mov [protocol_status], A
;
; test what kind of reset occurred 
;
	iord Status_Control
	and A, USBReset		; test for USB Bus Reset
	jnz BusReset

	iord Status_Control
	and A, WatchDogReset	; test for Watch Dog Reset
	jz suspendReset
;
; Process a watchdog reset.  Wait for a Bus Reset to bring the system
; alive again.
	mov A, TIMER_ONLY	; enable one msec timer interrupt
	mov [interrupt_mask],A
	iowr Global_Interrupt

WatchdogHandler:		; wait for USB Bus Reset
	jmp WatchdogHandler
suspendReset:
	mov A, 09h
	iowr Status_Control	; go back to suspend
	nop
	jmp suspendReset		; wait until real bus reset
;
; Either a bus reset or a normal reset has occurred
;
BusReset:
	mov A, RunBit		; clear all reset bits
	iowr Status_Control

; setup for enumeration
	mov A, ENUMERATE_MASK	
	mov [interrupt_mask],A
	iowr Global_Interrupt

wait:						; wait until configured
	iord USB_EP1_TX_Config			
	cmp A, 0		
	jz wait			

;************************************************************************
; This is the main loop that is entered after reset processing
;************************************************************************
;
main:
;	iowr	Watchdog		; clear watchdog timer
	jmp main

;************************************************************************
; Command string transmit processing:
; These 3 routines will transmit four bytes of data for each command.
; 1.) Ident: Manufacturer:  "I M C_R L_F"
; 2.) Ident: Product:       "I O C_R L_F"
; 3.) Ident: Serial Nunber: "I Z C_R L_F"
;************************************************************************
put_iManufacturer_String:
	push	A			; Save the accumulator.
	push	X			; Save the index register.
	call initialize_req
	mov   A, Asc_I		; Load ASCII 'I' into accumulator
	mov   [X + txBuf], A	; Write into the buffer.
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	; Load the new index.
	mov   A, Asc_M		; Load ASCII 'M' into accumulator
	call end_req
	pop	X			; Restore the index.
	pop	A			; Restore the accumulator.
	ret				; Return to caller.
;************************************************************************
put_iProduct_String:
	push	A			; Save the accumulator.
	push	X			; Save the index register.
	call initialize_req
	mov   A, Asc_I		; Load ASCII 'I' into accumulator.
	mov   [X + txBuf], A	; Write into the buffer.
	inc   [txBufPtr]		; Increment tx buffer pointer.
	mov	X, [txBufPtr]	; Load the new index.
	mov   A, Asc_O		; Load ASCII 'O' into accumulator.
	call end_req
	pop	X			; Restore the index register.
	pop	A			; Restore the accumulator.
	ret				; Return to caller.
;************************************************************************
put_iSerialNumber_String:
	push	A			; Save the accumulator.
	push	X			; Save the index register.
	call initialize_req
	mov   A, Asc_I		; Load ASCII 'I' into accumulator
	mov   [X + txBuf], A	; Write into the buffer.
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	; Load the new index.
	mov   A, Asc_Z		; Load ASCII 'Z' into accumulator
	call end_req
	pop	X			; Restore the index register.
	pop	A			; Restore the accumulator.
	ret				; Return to caller.

;************************************************************************
; This routine sends the strings
;************************************************************************
send_string: 
	push X				; save X on stack
	mov A, 00h				; clear data 0/1 bit
	mov [endp0_data_toggle], A		
	mov [rxBufPtr], A
	mov X, 0h
	iowr USB_EP0_RX_Status		; clear setup bit
; Fixing a bug seen by NEC hosts	
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz send_string_end		; has arrived. Exit ISR
	mov A, 08h				; set BADOUTS BIT
	iowr USB_Status_Control
	mov A, 03h
	mov [endpoint_0 + 1], A
	mov A, [data_count]
	cmp A, [temp2]
	jz right_length
;	mov A, 03h
;	mov [endpoint_0 + 1], A
	mov A, [temp2]
	mov [endpoint_0], A
	mov A, 01h
	mov [loop_counter], A
	dec [data_count]
	jz send_packet
	inc [loop_counter]
	dec [data_count]
	jz send_packet
;	mov A, [data_count]
;	asr A
;	mov [data_count], A	
	jmp sending_loop
right_length:
	mov A, [data_count]
	cmp A, 00h
	jz send_empty
first_byte:
	mov [endpoint_0], A
;	mov A, 03h
;	mov [endpoint_0 + 1], A
	mov A, 01h
	mov [loop_counter], A
	dec [data_count]
	mov A, [data_count]
	cmp A, 00h
	jz send_packet			
	dec [data_count]
	inc [loop_counter]			
	mov A, [data_count]
	cmp A, 00h
	jz send_packet

sending_loop:				; loop to load data into the data buffer
	mov X, [rxBufPtr]
	mov A, [X + rxBuf]
	mov X, [loop_counter]
	mov [X + endpoint_0], A		
	inc [rxBufPtr]
	inc [loop_counter]
	dec [data_count]
	cmp A, 0h
	jz send_packet						
	mov A, 00h
	mov X, [loop_counter]
	mov [X + endpoint_0], A		
	inc [loop_counter]
	dec [data_count]			
	mov A, [data_count]
	cmp A, 0h
	jz send_packet		
	mov A, [loop_counter]	
	cmp A, 08h
	jnz sending_loop

send_packet:
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz send_string_end	; has arrived. Exit ISR
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	or A, [loop_counter]
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

send_wait:
	iord USB_EP0_TX_Config		; wait for the data to be
	and A, 80h				; transfered
	jz next_packet
	iord USB_EP0_RX_Status
	and A, 02h				; check if out was sent by host
	jz send_wait
	jmp send_empty

next_packet:
	mov A, 0h
	mov [loop_counter], A
	iowr USB_EP0_RX_Status		; clear setup bit
; Fixing a bug seen by NEC hosts	
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz send_string_end		; has arrived. Exit ISR
	mov A, 08h				; set BADOUTS BIT
	iowr USB_Status_Control
	mov A, [data_count]
	cmp A, 00h
	jnz sending_loop

send_empty:
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	and A, 0f0h
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

send_string_end:				; OUT at end of data transfer
	pop X					; restore X from stack
	mov A, [interrupt_mask]
	iowr Global_Interrupt
	ret

;************************************************************************
; This routine arranges the strings and adds 00 byte after each ascii byte
; the length is also calculated and the strings are sent(calls send_string)
;************************************************************************
arrange_strings:
	mov A, 02h
	mov [data_count], A
	mov A, 03h
	mov [data_send + 1], A		; Report type
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_string
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_string
; Request is supported and no errors occured
; Count the bytes and send
	mov A, 0h		
	mov [rxBufPtr], A
	mov [data_count], A
next_string:
	mov X, [rxBufPtr]
	mov A, [X + rxBuf]
	cmp A, Car_Ret
	jz end_of_string
	inc [data_count]
	mov A, [data_count]
	cmp A, 10h			; check if 16 bytes
	jz end_of_string
	inc [rxBufPtr]
	jmp next_string
end_of_string:
	mov A, [data_count]
	asl A
	add A, 02h
	mov [data_count], A
	mov [temp2], A
	call get_descriptor_length	
	call send_string
	jmp arrange_strings_end
bad_string:
	inc [data_count]
	mov A, [data_count]
	mov [data_send], A		; Report type
	mov A, 0ffh
	mov [data_send + 2], A
	call get_descriptor_length
	call control_send
arrange_strings_end:
	ret
;********************************************************************************
; This routine initializes the sending of requests to the UPS
;********************************************************************************
initialize_req:
	call	delay			
	call	Clear_rxBuf
	mov	A, 00h		;
	mov	[rxBufPtr], A	; Reset the receive buffer pointer.
	mov	[txBufPtr], A	;
	mov	X, [txBufPtr]	;
	ret

;********************************************************************************
; This routine checks if 15,0D (unsupported request) has been returned from the UPS
; If a request is unsupported FFh is returned over the USB bus to the host
;********************************************************************************
unsupported_check:
	mov A, [rxBuf]		; Is the first byte 15h
	cmp A, 15h
	jnz supported
	mov A, [rxBuf + 1]	; Is the 2nd byte 0Dh
	cmp A, Car_Ret
	jnz supported
	mov A, 1h			; unsupported command
	mov [temp2], A
	jmp end_unsupported
supported:				; supported command
	mov A, 0h
	mov [temp2], A
end_unsupported:
	ret
;********************************************************************************
; This routine ends the transmission loading part, transmits the commands
; and receives the result from the UPS
;********************************************************************************
end_req:
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Car_Ret		; Load carriage return into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Ln_Fd		; Load line feed into accumulator
	mov   [X + txBuf], A	;
	call	putCommand		; Send command to UPS
	call	getSerial		; Receive result from UPS
	ret
;********************************************************************************
; This routine checks for error and loads two bytes to be sent
;********************************************************************************
get_two_bytes:
	call end_req		;send and receive the data from UPS
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value
; Request is supported and no errors occured
	call  ASCII_to_BCD	; change from ASCII to BCD
	mov A, [endpoint_1 + 2]
	mov X, [send_ptr]
	mov [X + data_send], A
	inc X
	inc [send_ptr]	
	mov A, [endpoint_1 + 1]
	mov [X + data_send], A	
	jmp next
bad_value:
; An error occured or an unsupported request
; fill sent back bytes with ffh
	mov A, 0ffh
	mov X, [send_ptr]
	mov [X + data_send], A
	inc X
	inc [send_ptr]
	mov [X + data_send], A
next:
	inc [send_ptr]
	call initialize_req	; initialize for next request
	ret

;********************************************************************************
; This routine checks for error and loads three bytes to be sent
;********************************************************************************
get_three_bytes:
	call end_req		;send and receive the data from UPS
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value2
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value2
; Request is supported and no errors occured
	call  ASCII_to_BCD	; change from ASCII to BCD
	mov A, [endpoint_1 + 2]
	mov X, [send_ptr]
	mov [X + data_send], A
	inc X
	inc [send_ptr]	
	mov A, [endpoint_1 + 1]
	mov [X + data_send], A	
	inc X
	inc [send_ptr]	
	mov A, [endpoint_1]
	mov [X + data_send], A	
	jmp next2
bad_value2:
; An error occured or an unsupported request
; fill sent back bytes with ffh
	mov A, 0ffh
	mov X, [send_ptr]
	mov [X + data_send], A
	inc X
	inc [send_ptr]
	mov [X + data_send], A
	inc X
	inc [send_ptr]
	mov [X + data_send], A
next2:
	inc [send_ptr]
	call initialize_req	; initialize for next request
	ret

;********************************************************************************
;		Report ID 1
;********************************************************************************
get_reportID1:
	push	A			;
	push	X			;
	mov A, 02h
	mov [send_ptr], A
	call initialize_req
;put_Main_ConfigVoltage_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_V		; Load ASCII 'V' into accumulator
	call get_two_bytes
;put_Main_ConfigFrequency_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	call get_two_bytes
;put_LowVoltageTransfer_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_L		; Load ASCII 'L' into accumulator
	call get_two_bytes
;put_HighVoltageTransfer_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_H		; Load ASCII 'H' into accumulator
	call get_two_bytes
	pop	X			;
	pop	A			;
	ret				;
;
;********************************************************************************
;		Report ID 2
;********************************************************************************
get_reportID2:
	push	A			;
	push	X			;
	mov A, 02h
	mov [send_ptr], A
	call initialize_req
;put_AC_ConfigVoltage_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_O		; Load ASCII 'O' into accumulator
	call get_two_bytes
;put_AC_ConfigFrequency_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_R		; Load ASCII 'R' into accumulator
	call get_two_bytes
;put_AC_ConfigApparentPower_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_A		; Load ASCII 'A' into accumulator
	call get_two_bytes
;put_AC_ConfigActivePower_String:
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_P		; Load ASCII 'P' into accumulator
	call get_two_bytes
;put_AC_DelayBeforeStartup_String:
	mov   A, Asc_C		; Load ASCII 'C' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_U		; Load ASCII 'U' into accumulator
	call get_three_bytes
;put_AC_DelayBeforeShutdown_String:
	mov   A, Asc_C		; Load ASCII 'C' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_S		; Load ASCII 'S' into accumulator
	call get_three_bytes
;
	pop	X			;
	pop	A			;
	ret				;
;
;********************************************************************************
;		Report ID 3
;********************************************************************************
get_reportID3:
	push	A			;
	push	X			;
	mov A, 03h
	mov [send_ptr], A
	call initialize_req
;put_Battery_PresentStatus_String:
	mov   A, Asc_A		; Load ASCII 'A' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_G		; Load ASCII 'G' into accumulator
	call end_req
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value31
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value31
; Request is supported and no errors occured
; No change to BCD needed
	mov A, [rxBuf]
	and A, 0fh
	asr A				; bit 0 = used, bit1 = bad
	mov [data_send + 2], A
	jmp next31
bad_value31:
	; fill sent back byte with ffh
	mov A, 0ffh
	mov [data_send + 2], A
next31:
	call initialize_req
;put_Battery_Voltage_String:
	mov   A, Asc_B		; Load ASCII 'B' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_V		; Load ASCII 'V' into accumulator
	call get_three_bytes
;put_Battery_Temperature_String:
	mov   A, Asc_B		; Load ASCII 'B' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_T		; Load ASCII 'T' into accumulator
	call get_two_bytes
;get_Battery_TestResults_String:
	mov   A, Asc_T		; Load ASCII 'T' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_R		; Load ASCII 'R' into accumulator
;	mov   A, Asc_D		; Load ASCII 'D' into accumulator
	call end_req
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value34
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value34
; Request is supported and no errors occured
; No change to BCD needed
	mov A, [rxBuf]
	and A, 0fh	
	mov [data_send + 8], A
	jmp next34
bad_value34:
	; fill sent back byte with ffh
	mov A, 0ffh
	mov [data_send + 8], A
next34:

	pop	X			;
	pop	A			;
	ret				;
;
;***************************************************************************
set_reportID3:
put_Battery_TestStart_String:
	push	A			;
	push	X			;

	mov	A, 00h		;
	mov	[txBufPtr], A	;
	mov	X, [txBufPtr]	;
	mov   A, Asc_T		; Load ASCII 'T' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_s		; Load ASCII 's' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Car_Ret		; Load carriage return into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Ln_Fd		; Load line feed into accumulator
	mov   [X + txBuf], A	;
;
	call	putCommand		;
;
	call	delay;
;
	pop	X			;
	pop	A			;
	ret

;********************************************************************************
;		Report ID 4
;********************************************************************************
get_reportID4:
	push	A			;
	push	X			;
	mov A, 04h
	mov [send_ptr], A
	call initialize_req
;put_PowerConverter_PresentStatus_String:
	mov   A, Asc_A		; Load ASCII 'A' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_G		; Load ASCII 'G' into accumulator
	call end_req
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value41
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value41
; Request is supported and no errors occured
; No conversion needed
	mov A, [rxBuf]
	and A, 02h
	asr A
;	asr A
;	asr A
;	asr A
;	asr A
	mov [data_send + 3], A
	jmp next41
bad_value41:
	; fill sent back byte with ffh
	mov A, 0ffh
	mov [data_send + 3], A
next41:
	call initialize_req
;put_PowerConverter_In_Voltage_String:
	mov   A, Asc_N		; Load ASCII 'N' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_V		; Load ASCII 'V' into accumulator
	call get_two_bytes
;put_PowerConverter_In_Frequency_String:
	mov   A, Asc_N		; Load ASCII 'N' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	call get_two_bytes
;
	pop	X			;
	pop	A			;
	ret				;
;

;********************************************************************************
;		Report ID 5
;********************************************************************************
get_reportID5:
	push	A			;
	push	X			;
	mov A, 02h
	mov [send_ptr], A
	call initialize_req
;put_PowerConverter_Out_Voltage_String:
	mov   A, Asc_O		; Load ASCII 'O' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_V		; Load ASCII 'V' into accumulator
	call get_two_bytes
;put_PowerConverter_Out_Frequency_String:
	mov   A, Asc_O		; Load ASCII 'O' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_F		; Load ASCII 'F' into accumulator
	call get_two_bytes
;put_PowerConverter_Out_Load_String:
	mov   A, Asc_O		; Load ASCII 'O' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_L		; Load ASCII 'L' into accumulator
	call get_two_bytes
;put_PowerConverter_Out_PresStat_String:
	mov   A, Asc_A		; Load ASCII 'A' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_G		; Load ASCII 'G' into accumulator
	call end_req
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value54
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value54
; Request is supported and no errors occured
; No conversion needed
	mov A, [rxBuf]
	and A, 08h
	cmp A, 08h
	jnz no_overload
	mov A, 01h
	jmp save_value
no_overload:
	mov A, 00h
save_value:
	mov [data_send + 8], A
; Get boost and buck
	call initialize_req
	mov   A, Asc_O		; Load ASCII 'O' into accumulator
	mov   [X + txBuf], A	;
	inc   [txBufPtr]		; Increment tx buffer pointer
	mov	X, [txBufPtr]	;
	mov   A, Asc_S		; Load ASCII 'S' into accumulator
	call end_req
; Check if an error has occured during communication with the UPS
	mov A, [rxFrameFlag]
	cmp A, 01h
	jz bad_value54
; NO error in the UPS communication
	call unsupported_check	; check if the request unsupported
;	mov A, [temp2]
	cmp A, 01h
	jz bad_value54
; Request is supported and no errors occured
; No conversion needed
	mov A, [rxBuf]
	and A, 0fh
	cmp A, 06h
	jz set_boost
	cmp A, 07h
	jz set_buck
	jmp next54
set_boost:
	mov A, [data_send + 8]
	or A, 02h
	mov [data_send + 8], A
	jmp next54
set_buck:
	mov A, [data_send + 8]
	or A, 04h
	mov [data_send + 8], A
	jmp next54		
bad_value54:
	; fill sent back byte with ffh
	mov A, 0ffh
	mov [data_send + 8], A
next54:

	pop	X			;
	pop	A			;
	ret				;

;************************************************************************
; This is the routine that is entered when a data item from the UPS is 
; requested and returns with the string resident in the receive buffer.
;************************************************************************
;
putCommand:
	mov	A, 00h		; Clear the accumulator.
	mov   [txBufPtr], A	; Reset tx buffer pointer.
	iowr	Watchdog		; Clear watchdog timer.
	mov	X, [txBufPtr]	; Set the index.
	mov	A, [X + txBuf]	; Load Command Byte Zero.
	mov	[txData], A		; Put it in the transmit register.
	inc	[txBufPtr]		; Point to the next byte.
	iowr	Watchdog		; Ping the watch dog timer.
	call	txRoutine		; Go transmit the byte.
	iowr	Watchdog		; Ping the watch dog timer.
	call	delay1		; Give the serial device some time.
;	iowr	Watchdog		; clear watchdog timer
	mov	X, [txBufPtr]	; Set the index.
	mov	A, [X + txBuf]	; Load Command Byte One
	mov	[txData], A		; Put it in the transmit register.
	inc	[txBufPtr]		; Point to the next byte.
	iowr	Watchdog		; clear watchdog timer
	call	txRoutine		; Go transmit the byte.
	iowr	Watchdog		; clear watchdog timer
	call	delay1		; Give the serial device some time.
;	iowr	Watchdog		; clear watchdog timer
	mov	X, [txBufPtr]	; Set the index.
	mov	A, [X + txBuf]	; Load Command Byte Two
	mov	[txData], A		; Put it in the transmit register.
	inc	[txBufPtr]		; Point to the next byte.
;	iowr	Watchdog		; clear watchdog timer
	call	txRoutine		; Go transmit the byte.
	iowr	Watchdog		; clear watchdog timer
;	call	delay1		; Give the serial device some time.
;	iowr	Watchdog		; clear watchdog timer
	mov	X, [txBufPtr]	; Set the index.
	mov	A, [X + txBuf]	; Load Command Byte Three
	mov	[txData], A		; Put it in the transmit register.
	inc	[txBufPtr]		; Point to the next byte.
;	iowr	Watchdog		; clear watchdog timer
	call	txRoutine		; Go transmit the byte.
	mov	A, 80h		; Enable the Port 0 Bit 7
	iowr	Port0_Interrupt	; GPIO interrupt.
	iowr	Watchdog		; clear watchdog timer
	ret				; Return to sender.
;
;************************************************************************
; This routine changes from ASCII to BCD
;************************************************************************
ASCII_to_BCD:
;
	push A	
	push X	
	mov A, 0h		
	mov [rxBufPtr], A
	mov A, 02h
	mov [temp2], A
next_char:
	mov X, [rxBufPtr]
	mov A, [X + rxBuf]
	cmp A, Car_Ret
	jz end_of_data
	and A, 0fh
	mov [X + rxBuf], A
	inc [rxBufPtr]
	jmp next_char
end_of_data:
	dec [rxBufPtr]
	jc end_conversion
	mov X, [rxBufPtr]
	mov A, [X + rxBuf]
	mov X, [temp2]
	mov [X + endpoint_1], A
	dec [rxBufPtr]
	jc end_conversion
	mov X, [rxBufPtr]
	mov A, [X + rxBuf]
	asl A
	asl A
	asl A
	asl A
	mov X, [temp2]	
	or A, [X + endpoint_1]
	mov [X + endpoint_1], A
	dec [temp2]
	jmp end_of_data
end_conversion:
	pop X
	pop A
	ret
;************************************************************************
;
;	Interrupt handler: endpoint_zero
;	Purpose: This interrupt routine handles the specially
;		 reserved control endpoint 0 and parses setup 
;		 packets.  If a IN or OUT is received, this 
;		 handler returns to the control_read
;		 or no_data_control routines to send more data.
;
;************************************************************************
; The endpoint zero interrupt service routine supports the control
; endpoint.  This firmware enumerates and configures the hardware.
;************************************************************************
USB_EP0_ISR:
      push A                  		; save accumulator on stack
	iord USB_EP0_RX_Status			; load status register into accumulator
	and A, 01h					; check if SETUP packet received
	jz ep0_continue				; ignore unless SETUP packet 
	mov A,[interrupt_mask]			; disable endpoint zero interrupts
	and A, 0F7h
	mov [interrupt_mask], A
	iowr Global_Interrupt
      call StageOne           		; parse SETUP packet
	mov A, [interrupt_mask]			; enable endpoint zero interrupts
	or A, 08h
	mov [interrupt_mask], A	
ep0_continue:
	mov A, [interrupt_mask]			; enable the interrupts
	ipret Global_Interrupt

;========================================================================
;       stage one ... test bmRequestType
;========================================================================
StageOne:
;------------------------------------------------------------------------
; Parse standard device requests as per Table 9.2 in USB Spec.
;------------------------------------------------------------------------
	mov A, 00h					; clear the setup flag to write DMA
	iowr USB_EP0_RX_Status
	mov A, 8					; set BadOut bit
	iowr USB_Status_Control
      mov A, [bmRequestType]  		; load bmRequestType
; host to device
        cmp A, 00h
        jz RequestType00        		; bmRequestType = 00000000 device
;       cmp A, 01h              		*** not required ***  
;       jz RequestType01        		; bmRequestType = 00000001 interface
        cmp A, 02h              
        jz RequestType02        		; bmRequestType = 00000010 endpoint
        cmp A, 80h             
; device to host
        jz RequestType80        		; bmRequestType = 10000000 device
        cmp A, 81h
        jz RequestType81       		; bmRequestType = 10000001 interface
        cmp A, 82h
        jz RequestType82       		; bmRequestType = 10000010 endpoint
;-----------------------------------------------------------------------
; Parse HID class device requests as per HID version 1.0 Draft #4
;-----------------------------------------------------------------------
; host to device
        cmp A, 21h
        jz RequestType21        		; bmRequestType = 00100001 interface
        cmp A, 22h             		; *** not in HID spec ***
        jz RequestType22       		; bmRequestType = 00100010 endpoint
; device to host
        cmp A, A1h
        jz RequestTypeA1        		; bmRequestType = 10100001 interface

;-----------------------------------------------------------------------
; Stall unsupported functions
;-----------------------------------------------------------------------
SendStall:						; stall unsupported functions
      mov A, A0h					; send a stall to indicate the requested
	iowr USB_EP0_TX_Config			; function is not supported
      ret                    			; return
;========================================================================
;       stage two ... test bRequest
;========================================================================
; host to device with device as recipient
RequestType00:
	mov A, [bRequest]	; load bRequest
;------------------------------------------------------------------------
; The only standard feature defined for a "device" recipient is
; device_remote_wakeup.  Remote wakeup is the ability to "wakeup" a
; system from power down mode by pressing a key or moving a button.
; The default condition at reset is remote wakeup disabled.
;------------------------------------------------------------------------
; Clear Feature                 	bRequest = 1
        cmp A, clear_feature
        jz ClearRemoteWakeup 
; Set Feature 				bRequest = 3
	cmp A, set_feature
        jz SetRemoteWakeup
;------------------------------------------------------------------------
; Set the device address to a non-zero value.
; Set Address 				bRequest = 5
	cmp A, set_address
	jz SetAddress
;------------------------------------------------------------------------
; This request is optional.  If a device supports this request, existing
; device descriptors may be updated or new descriptors may be added.
; Set Descriptor                bRequest = 7    *** not supported ***
;------------------------------------------------------------------------
; If wValue is zero, the device is unconfigured.  The only other legal
; configuration for this version of firmware is one.
; Set Configuration 		bRequest = 9
	cmp A, set_configuration
	jz SetConfiguration
    	jmp SendStall           ; stall unsupported function calls
                                                       
;========================================================================
; host to device with interface as recipient    *** not required ***
; RequestType01:
;        mov A, [bRequest]       ; load bRequest
;------------------------------------------------------------------------
; There are no interface features defined in the spec.
; Clear Feature                 bRequest = 1    *** not supported ***
; Set Feature                   bRequest = 3    *** not supported ***
;------------------------------------------------------------------------
; This request allows the host to select an alternate setting for the
; specified interface.  As only one interface setting is being used,
; this request is not supported.
; Set Interface                 bRequest = 11   *** not supported ***
;        jmp SendStall           ; stall unsupported functions

;========================================================================
; host to device with endpoint as recipient
RequestType02:
	mov A, [bRequest]	; load bRequest
;------------------------------------------------------------------------
; The only standard feature defined for an endpoint is endpoint_stalled.  
; Clear Feature			bRequest = 1
	cmp A, clear_feature
      jz ClearEndpointStall
; Set Feature			bRequest = 3
	cmp A, set_feature
      jz SetEndpointStall
	jmp SendStall		; stall unsupported functions

;=======================================================================
; device to host with device as recipient
RequestType80:
	mov A, [bRequest]		; load bRequest
; Get Status			bRequest = 0
	cmp A, get_status
      jz GetDeviceStatus
; Get Descriptor			bRequest = 6
	cmp A, get_descriptor
	jz GetDescriptor
; Get Configuration		bRequest = 8
	cmp A, get_configuration
	jz GetConfiguration
	jmp SendStall		; stall unsuported functions

;=======================================================================
; device to host with interface as recipient
RequestType81:
	mov A, [bRequest]	; load bRequest
; Get Status			bRequest = 0
      cmp A, get_status
      jz GetInterfaceStatus
;------------------------------------------------------------------------
; This request returns the selected alternate setting for the specified
; interface.  There are no alternate settings for the in this UPS.
; Get Interface                 bRequest = 10   *** not supported ***
;------------------------------------------------------------------------
; HID class defines one more request for bmRequestType=10000001
; Get Descriptor                bRequest = 6
      cmp A, get_descriptor
      jz GetDescriptor
	jmp SendStall		; stall unsupported functions

;=======================================================================
; device to host with endpoint as recipient
RequestType82:
	mov A, [bRequest]		; load bRequest
; Get Status			bRequest = 0
	cmp A, get_status
      jz GetEndpointStatus
;------------------------------------------------------------------------
; Not defined in the spec, but it must be decoded for the enumeration to
; complete under Memphis.
; Get Descriptor			bRequest = 6
	cmp A, get_descriptor
	jz GetDescriptor
; Sync Frame                  bRequest = 12   *** not supported ***
	jmp SendStall		; stall unsupported functions

;========================================================================
;	Now parse HID class Descriptor Types
;========================================================================
; host to device with endpoint as recipient
RequestType21:
      mov A, [bRequest] 	; load bRequest
; Set Report			bRequest = 9
	cmp A, set_report
	jz SetReport
; Set Idle				bRequest = 10
      cmp A, set_idle
      jz SetIdle
; Set Protocol			bRequest = 11
      cmp A, set_protocol
      jz SetProtocol
	jmp SendStall		; stall unsupported functions

;=======================================================================
; This one is not in the spec, but has been captured with CATC while
; Memphis beta testing. 
RequestType22:
      mov A, [bRequest] 	; load bRequest
; Set Report			bRequest = 9
	cmp A, set_report	
	jz SetReport
	jmp SendStall		; stall unsupported functions

;=======================================================================
; device to host with endpoint as recipient
RequestTypeA1:
        mov A, [bRequest] 	; load bRequest
; Get Report			bRequest = 1
        cmp A, get_report
        jz GetReport
; Get Idle				bRequest = 2
        cmp A, get_idle
        jz GetIdle
; Get Protocol			bRequest = 3
        cmp A, get_protocol
        jz GetProtocol
        jmp SendStall        	; stall unsupported functions

;========================================================================
;       stage three ... process the request
;========================================================================
; Remote wakeup is the ability to wakeup a system from power down mode.
; These routines allow the host to enable/disable the ability to request 
; remote wakeup.
;
; Disable the remote wakeup capability.
ClearRemoteWakeup:
        mov A, [wValue]                 ; load wValue
        cmp A, device_remote_wakeup     ; test for valid feature
        jnz SendStall                   ; stall unsupported features
        call no_data_control            ; handshake with host
        mov A, DISABLE_REMOTE_WAKEUP    ; disable remote wakeup
        mov [remote_wakeup_status], A
        ret                             ; return

; Enable the remote wakeup capability.
SetRemoteWakeup:
        mov A, [wValue]                 ; load wValue
        cmp A, device_remote_wakeup     ; test for valid feature
        jnz SendStall                   ; stall unsupported features
        call no_data_control            ; handshake with host
        mov A, ENABLE_REMOTE_WAKEUP     ; enable remote wakeup
        mov [remote_wakeup_status], A
        ret                             ; return

; Set the device address to the wValue in the SETUP packet at
; the completion of the current transaction.
SetAddress:
        call no_data_control            ; handshake with host
        mov A, [wValue]                 ; load wValue 
        iowr USB_Device_Address         ; write new USB device address
        ret                             ; return

; Set the configuration of the device to either unconfigured (0) or
; configured (1) based on wValue in the SETUP packet.  According to
; the USB spec (page 178), a Set Configuration also clears the endpoint
; stall condition and re-initializes endpoints using data 0/1 toggle to
; Data0.
SetConfiguration:
      call no_data_control
	mov A, [wValue]				; load wValue lsb
      mov [configuration_status], A   	; store configuration byte
      mov A, 0
      mov [endpoint_stall], A  		; not stalled
      iord USB_EP1_TX_Config          	; clear data 0/1 bit
      and A, ~DataToggle
	iowr USB_EP1_TX_Config	
      mov A, [configuration_status]
      cmp A, 0
	jnz device_configured

; device is unconfigured
	iord USB_EP1_TX_Config
	and A, EFh					; disable endpoint 1
	iowr USB_EP1_TX_Config			  
	mov A, [interrupt_mask]			; disable endpoint one interrupts
	and A, EFh
    	mov [interrupt_mask], A
	jmp done_configuration

; device is configured
device_configured:
	iord USB_EP1_TX_Config		; NAK IN packets until data is 	
	and A,7Fh				; ready on endpoint one
	or A, 10h				; enable endpoint one
	iowr USB_EP1_TX_Config			  
	mov A, [interrupt_mask]		; enable endpoint one interrupts
	or A, 10h
    	mov [interrupt_mask], A
      iord USB_Status_Control		; NAK IN packets until data is 	
	and A,0EFh				; ready on endpoint one
	iowr USB_Status_Control			  
done_configuration:		  
        ret                         ; return

; Clear the endpoint stall feature for the selected endpoint.  This
; should also set the data 0/1 bit to Data0 if endpoint one is selected.
ClearEndpointStall:
        mov A, [wValue]                 ; load wValue (which feature)
        cmp A, endpoint_stalled         ; test for valid feature
        jnz SendStall                   ; stall unsupported features
;
; clear endpoint one stall feature
;
      call no_data_control            	; handshake with host
      mov A,0         
      mov [endpoint_stall], A  		; not stalled
      iord USB_EP1_TX_Config          	; clear data 0/1 bit
      and A, ~DataToggle
	iowr USB_EP1_TX_Config		
      iord USB_Status_Control			; NAK IN packets until data is 	
	and A,0EFh					; ready on endpoint one
	iowr USB_Status_Control			  
      ret                             	; return

; Set the endpoint stall feature for the selected endpoint.
SetEndpointStall:
        mov A, [wValue]                 	; load wValue
        cmp A, endpoint_stalled         	; test for valid feature
        jnz SendStall                   	; stall unsupported features
        call no_data_control            	; handshake with host
        mov A,1         
        mov [endpoint_stall], A  		; stalled
        mov A, 30h                    	; stall endpoint one 
        iowr USB_EP1_TX_Config                 
        ret                             	; return

; The device status is a 16-bit value (two bytes) with only D[1:0]
; defined.  D0=0 specifies bus-powered, which never changes.  D1
; reflects the status of the device_remote_wakeup feature.  This
; feature can either be disabled (D1=0) or enabled (D1=1).
GetDeviceStatus:
        mov A, 2                        		; send two bytes
        mov [data_count], A
        mov A, (get_dev_status_table - control_read_table)
        add A, [remote_wakeup_status]   		; get correct remote wakeup
        jmp execute                     		; send device status to host

; There are five descriptor types.  The descriptor type will be in
; the high byte of wValue.  The descriptor index will be in the low
; byte of wValue.  The standard request to a device supports three
; of these types: device, configuration, and string.  The standard
; request does not support interface or endpoint descriptor types.
GetDescriptor:
        mov A, [wValueHi]               ; load descriptor type
;------------------------------------------------------------------------
; Test for standard descriptor types first.
; Get Descriptor (device)               wValueHi = 1
	cmp A, device
      jz GetDeviceDescriptor
; Get Descriptor (configuration)        wValueHi = 2
	cmp A, configuration
      jz GetConfigurationDescriptor
; Get Descriptor (string)               wValueHi = 3
	cmp A, string
	jz GetStringDescriptor
;------------------------------------------------------------------------
; Then test for HID class descriptor types.
; Get Descriptor (HID)                  wValueHi = 21h
        cmp A, HID
        jz GetHIDDescriptor
; Get Descriptor (report)               wValueHi = 22h  
	cmp A, report
	jz GetReportDescriptor
; Get Descriptor (physical)             wValueHi = 23h  *** not supported ***
	jmp SendStall			    ; stall unsupported functions

; Return the current device configuration to the host.  The possible
; values are zero (unconfigured) and one (configured).
GetConfiguration:
        mov A, 1                        ; send one byte
        mov [data_count], A
        mov A, (get_configuration_status_table - control_read_table)
        add A, [configuration_status]   ; get correct configuration
        jmp execute                     ; send configuration to host

; The interface status is a 16-bit value (two bytes) that is always
; zero for both bytes.
GetInterfaceStatus:
        mov A, 2                        ; send two bytes
        mov [data_count], A
        mov A, (get_interface_status_table - control_read_table)
        jmp execute                     ; send interface status to host

; The endpoint status is a 16-bit value (two bytes) with only one
; bit (D0) defined.  If D0=0, then the selected endpoint is not
; stalled.  If D0=1, then the selected endpoint is stalled.
GetEndpointStatus:
        mov A, 2                        ; send two bytes
        mov [data_count], A
        mov A, [endpoint_stall]
        asl A                           ; select the correct entry
        add A, (get_endpoint_status_table - control_read_table)
        jmp execute                     ; send endpoint status to host

;------------------------------------------------------------------------
; Set Report   
SetReport:
	mov A, [wValue]
	cmp A, 03h
	jz set_ID3
	jmp SendStall	; *** unknown report ***
; SetReport ID3 is used to send a test command to the UPS
set_ID3:
	call set_reportID3
	ret
; Set Idle silences a particular report on the interrupt pipe until a new
; event occurs or the specified amount of time (wValue) passes.
SetIdle:
        jmp SendStall   ; *** not supported ***

; Set Protocol switches between the boot protocol and the report protocol.
; For boot protocol, wValue=0.  For report protocol, wValue=1.
SetProtocol:
        mov A, [wValue]                 ; load wValue
        mov [protocol_status], A        ; write new protocol value
        call no_data_control            ; handshake with host
        ret                             ; return

; Get Report allows the host to receive a report via the control pipe.
; The report type is specified in the wValue high byte while the low
; byte has a report ID.  
GetReport:
	mov A, [wValue]
	cmp A, 1h
	jz get_ID1
	cmp A, 2h
	jz get_ID2
	cmp A, 3h
	jz get_ID3
	cmp A, 4h
	jz get_ID4
	cmp A, 5h
	jz get_ID5
	jmp SendStall			  ; unknown report
get_ID1:
	mov A, 0Dh
	mov [data_count], A
	mov A, 01h
	mov [data_send], A		; Report ID
	mov [data_send + 1], A		; Flow ID
	mov [data_send + 0Ah], A		; Manufacturer name index
	mov A, 02h
	mov [data_send + 0Bh], A		; Product index
	mov A, 03h
	mov [data_send + 0Ch], A		; Serial Number index
	call get_reportID1
	call control_send
	jmp GetReport_end
get_ID2:
	mov A, 10h
	mov [data_count], A
	mov A, 02h
	mov [data_send], A		; Report ID
	mov A, 03h
	mov [data_send + 1], A		; Flow ID
	call get_reportID2
	call control_send
	jmp GetReport_end
get_ID3:
	mov A, 09h
	mov [data_count], A
	mov A, 03h
	mov [data_send], A		; Report ID
	mov A, 01h
	mov [data_send + 1], A		; Battery System ID
	call get_reportID3
	call control_send
	jmp GetReport_end
get_ID4:
	mov A, 08h
	mov [data_count], A
	mov A, 04h
	mov [data_send], A		; Report ID
	mov A, 01h
	mov [data_send + 1], A		; Power Converter ID
	mov A, 11h
	mov [data_send + 2], A		; Input and Flow ID
	call get_reportID4
	call control_send
	jmp GetReport_end
get_ID5:
	mov A, 09h
	mov [data_count], A
	mov A, 05h
	mov [data_send], A		; Report ID
	mov A, 13h
	mov [data_send + 1], A		; Output and Flow ID
	call get_reportID5
	call control_send
GetReport_end:
	ret
;**********************************************************
; supports hid reports larger than 256 bytes
;**********************************************************
GetReportDescriptor:
	mov A, 7h 
	index Class_Descriptor
      mov [low_data_count], A             ; save descriptor length            
      mov [data_count], A             ; save descriptor length            
	mov A, 8h 
	index Class_Descriptor 
      mov [hi_data_count], A             ; save descriptor length 
	cmp A, 0h
	jnz sixteen_bits
; 8 bits ( < 256 bytes in length)          	
;	mov A, (end_hid_report_desc_table - hid_report_desc_table)
;      mov [data_count], A             ; save descriptor length            
	mov A, (hid_report_desc_table - control_read_table)
      call execute                    ; send descriptor to host
	jmp GetReportDescriptor_end
sixteen_bits:
	call control_read_16

GetReportDescriptor_end:
      ret                           ; return

; Get Idle reads the current idle rate for a particular input report.
GetIdle:
        jmp SendStall   		; *** not supported ***

; Get Protocol sends the current protocol status back to the host.
GetProtocol:
        mov A, 1                        ; send one byte
        mov [data_count], A
        mov A, (get_protocol_status_table - control_read_table)
        add A, [protocol_status]        ; get correct configuration
        jmp execute                     ; send protocol to host
        
;========================================================================
; Standard Get Descriptor routines
;
; Return the device descriptor to the host.
GetDeviceDescriptor:
        mov A, 0                        ; load the device descriptor length
	  index device_desc_table
        mov [data_count], A             ; save the device descriptor length
        mov A, (device_desc_table - control_read_table)
        jmp execute                     ; send the device descriptor

; Return the configuration, interface, and endpoint descriptors.
GetConfigurationDescriptor:
	mov A, (end_config_desc_table - config_desc_table)
      mov [data_count], A               ; save the descriptor length
	mov A, (config_desc_table - control_read_table)
execute:                                ; send the descriptors
        mov [data_start], A             ; save start index
        call get_descriptor_length      ; correct the descriptor length
        call control_read               ; perform control read function
        ret                             ; return
GetStringDescriptor:
	mov A, [wValue]
	cmp A, 0h
	jz LanguageString
	cmp A, 01h
	jz ManufacturerString
	cmp A, 02h
	jz ProductString
	cmp A, 03h
	jz SerialNumString
; No other strings supported
      jmp SendStall   		; *** not supported ***
LanguageString:
	mov A, (USBStringDescription1 - USBStringLanguageDescription)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringLanguageDescription - control_read_table)
      jmp execute                     ; send the string descriptor
; Commented parts show how these strings could be implemented if ROM
; was used
ManufacturerString:	
;	mov A, ( USBStringDescription2 - USBStringDescription1)
;     mov [data_count], A               ; save the descriptor length
;	mov A, (USBStringDescription1 - control_read_table)
;      jmp execute                     ; send the string descriptor
	call put_iManufacturer_String
	call arrange_strings
	jmp end_string_desc
ProductString:
;	mov A, ( USBStringDescription3 - USBStringDescription2)
;     mov [data_count], A               ; save the descriptor length
;	mov A, (USBStringDescription2 - control_read_table)
;      jmp execute                     ; send the string descriptor
	call put_iProduct_String
	call arrange_strings
	jmp end_string_desc
SerialNumString:
;	mov A, ( USBStringEnd - USBStringDescription3)
;      mov [data_count], A               ; save the descriptor length
;	mov A, (USBStringDescription3 - control_read_table)
;     jmp execute                     ; send the string descriptor
	call put_iSerialNumber_String
	call arrange_strings
end_string_desc:
	ret
;------------------------------------------------------------------------
; HID class Get Descriptor routines
;
; Return the HID descriptor and enable endpoint one.
GetHIDDescriptor:
	mov A, (Endpoint_Descriptor - Class_Descriptor)
      mov [data_count], A             ; save descriptor length            
	mov A, ( Class_Descriptor - control_read_table)
      call execute                    ; send descriptor to host
      ret                             ; return

;**********USB library main routines*******************

;******************************************************
; The host sometimes lies about the number of bytes it
; wants from a descriptor.  Any request to get descriptor
; should return the lesser of the number of bytes requested
; or the actual length of the descriptor.
 
get_descriptor_length:
	mov A, [wLengthHi] 	; load requested transfer length
	cmp A, 0			; confirm high byte is zero
	jnz use_actual_length	; no requests should be longer than 256b
	mov A, [wLength]		; test low byte against zero
	cmp A, 0
	jz use_actual_length	; must request some data
	cmp A, [data_count]     ; compare to the amount of data
	jnc use_actual_length
	mov [data_count], A     ; use requested length
use_actual_length:
        ret                   ; return

;========================================================================
;	function: no_data_control
;	purpose: performs the no-data control operation
;		as defined by the USB specifications
no_data_control:
	mov A, C0h			; set up the transfer
	iowr USB_EP0_TX_Config	; register for data1
					; and 0 byte transfer

	mov A, [interrupt_mask]	; enable interrupts
	iowr Global_Interrupt

wait_nodata_sent:
	iord USB_EP0_TX_Config	; wait for the data to be
	and A, 80h			; transferred
	jnz wait_nodata_sent
	ret				; return to caller

;========================================================================

;******************************************************
;
;	function:  Control_read
;	Purpose:   Performs the control read operation
;		   as defined by the USB specification
;	SETUP-IN-IN-IN...OUT
;
;	data_start: must be set to the descriptors info
;		    as an offset from the beginning of the
;		    control read table
;		    data count holds the 
;	data_count: must be set to the size of the 
;		    descriptor 
; 	data read from ROM
;******************************************************

control_read: 
	push X				; save X on stack
	mov A, 00h				; clear data 0/1 bit
	mov [endp0_data_toggle], A

control_read_data_stage:
	mov X, 00h
	mov A, 00h
	mov [loop_counter], A
	iowr USB_EP0_RX_Status		; clear setup bit

; Fixing a bug seen by NEC hosts	
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz control_read_status_stage	; has arrived. Exit ISR
	mov A, 08h				; set BADOUTS BIT
	iowr USB_Status_Control
	mov A, [data_count]
	cmp A, 00h
	jz control_read_status_stage

dma_load_loop:				; loop to load data into the data buffer
	mov A, [data_start]
	index control_read_table
	mov [X + endpoint_0], A		; load dma buffer
	inc [data_start]
	inc X
	inc [loop_counter]
	dec [data_count]			; exit if descriptor
	jz dma_load_done			; is done
	mov A, [loop_counter]		; or 8 bytes sent
	cmp A, 08h
	jnz dma_load_loop

dma_load_done:

	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz control_read_status_stage	; has arrived. Exit ISR
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	or A, [loop_counter]
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

wait_control_read:
	iord USB_EP0_TX_Config		; wait for the data to be
	and A, 80h				; transfered
	jz control_read_data_stage
	iord USB_EP0_RX_Status
	and A, 02h				; check if out was sent by host
	jz wait_control_read

control_read_status_stage:		; OUT at end of data transfer
	pop X					; restore X from stack
	mov A, [interrupt_mask]
	iowr Global_Interrupt
	ret

;******************************************************
;
;	function:  Control_read_16
;	Purpose:   Performs the control read operation
;		   as defined by the USB specification
;	SETUP-IN-IN-IN...OUT
;	This function is used for > 256 bytes of length
;	length in hi_data_count and low_data_count
; 	data read from ROM
;******************************************************

control_read_16: 
	push X				; save X on stack
	mov A, 00h				; clear data 0/1 bit
	mov [endp0_data_toggle], A
	mov A, 01h
	mov [loop_num], A
loop_256:
	mov A, 0ffh
	mov [data_count], A
	mov A, 0h
	mov [data_start], A

control_read_data_stage_16:
	mov X, 00h
	mov A, 00h
	mov [loop_counter], A
	iowr USB_EP0_RX_Status		; clear setup bit

; Fixing a bug seen by NEC hosts	
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz control_read_status_stage_16	; has arrived. Exit ISR
	mov A, 08h				; set BADOUTS BIT
	iowr USB_Status_Control
	mov A, [loop_num]
	cmp A, 04h
;	mov A, [data_count]
;	cmp A, 00h
	jz control_read_end
;	jz next_loop
	
dma_load_loop_16:				; loop to load data into the data buffer
	mov A, [loop_num]
	cmp A, 01h
	jz loop_one
	cmp A, 02h
	jz loop_two
	jmp loop_three
loop_one:
	mov A, [data_start]	
	index hid_report_desc_table
	jmp all_loop
loop_two:
	mov A, [data_start]	
	index (hid_report_desc_table + 0ffh)
	jmp all_loop
loop_three:
	mov A, [data_start]	
	index (hid_report_desc_table + 0ffh + 0ffh)
all_loop:
;	index control_read_table
	mov [X + endpoint_0], A		; load dma buffer
	inc [data_start]
	inc X
	inc [loop_counter]
	dec [data_count]			; exit if descriptor
	jz next_loop
;	jz dma_load_done_16			; is done
	mov A, [loop_counter]		; or 8 bytes sent
	cmp A, 08h
	jnz dma_load_loop_16

dma_load_done_16:

	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz control_read_status_stage_16	; has arrived. Exit ISR
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	or A, [loop_counter]
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

wait_control_read_16:
	iord USB_EP0_TX_Config		; wait for the data to be
	and A, 80h				; transfered
	jz control_read_data_stage_16
	iord USB_EP0_RX_Status
	and A, 02h				; check if out was sent by host
	jz wait_control_read_16
	jmp control_read_status_stage_16
next_loop:
	inc [loop_num]
	mov A, [loop_num]
	cmp A, 04h
;	jz control_read_status_stage_16 
	jz dma_load_done_16
	dec [hi_data_count]
	jz last_loop
;	jmp loop_256
	mov A, 0ffh
	mov [data_count], A
	mov A, 0h
	mov [data_start], A
	jmp dma_load_loop_16
last_loop:
	mov A, [low_data_count]
	add A, 02h
	mov [data_count], A
	mov A, 0h
	mov [data_start], A
;	jmp control_read_data_stage_16
	jmp dma_load_loop_16
	
control_read_end:
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	and A, 0f0h
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

control_read_status_stage_16:		; OUT at end of data transfer
	pop X					; restore X from stack
	mov A, [interrupt_mask]
	iowr Global_Interrupt
	ret

;******************************************************
;
;	function:  Control_send
;	Purpose:   Performs the control read operation
;		   as defined by the USB specification
;	SETUP-IN-IN-IN...OUT
;
; 	data read from RAM
;******************************************************

control_send: 
	push X				; save X on stack
	mov A, 00h				; clear data 0/1 bit
	mov [endp0_data_toggle], A
;	mov A, 08h
;	mov [data_count], A
	mov A, 0h
	mov [data_start], A
control_send_data_stage:
	mov X, 0h
	mov A, 0h
	mov [loop_counter], A
	iowr USB_EP0_RX_Status		; clear setup bit

; Fixing a bug seen by NEC hosts	
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz send_control_read_status_stage	; has arrived. Exit ISR
	mov A, 08h				; set BADOUTS BIT
	iowr USB_Status_Control
	mov A, [data_count]
	cmp A, 00h
	jz control_send_end
;	jz send_control_read_status_stage

send_dma_load_loop:				; loop to load data into the data buffer
	mov X, [data_start]
	mov A, [X + data_send]
;	index control_read_table
	mov X, [loop_counter]
	mov [X + endpoint_0], A		; load dma buffer
	inc [data_start]
;	inc X
	inc [loop_counter]
	dec [data_count]			; exit if descriptor
	jz send_dma_load_done			; is done
	mov A, [loop_counter]		; or 8 bytes sent
	cmp A, 08h
	jnz send_dma_load_loop

send_dma_load_done:

	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz send_control_read_status_stage	; has arrived. Exit ISR
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	or A, [loop_counter]
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

send_wait_control_read:
	iord USB_EP0_TX_Config		; wait for the data to be
	and A, 80h				; transfered
	jz control_send_data_stage
	iord USB_EP0_RX_Status
	and A, 02h				; check if out was sent by host
	jz send_wait_control_read

control_send_end:
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	and A, 0f0h
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

send_control_read_status_stage:		; OUT at end of data transfer
	pop X					; restore X from stack
	mov A, [interrupt_mask]
	iowr Global_Interrupt
	ret

;*********************************************************
;                   rom lookup tables
;*********************************************************

	XPAGEOFF
		
control_read_table:
   device_desc_table:
	db 12h          ; Descriptor length (18 bytes)
	db 01h          ; Descriptor type (Device)
	db 00h,01h      ; Complies to USB Spec. Release (1.00)
	db 00h          ; Class code (0)
	db 00h          ; Subclass code (0)
	db 00h          ; Protocol (No specific protocol)
	db 08h          ; Max. packet size for EP0 (8 bytes)
	db 43h,05h      ; Vendor ID (ViewSonic = 0x0543 = d1347)
	db 00h,00h      ; Product ID (UPS = 0x000)
	db 00h,01h      ; Device release number (1.00)
	db 01h          ; Mfr string descriptor index (00)
	db 02h          ; Product string descriptor index (32)
	db 03h          ; Serial Number string descriptor index (64)
	db 01h          ; Number of possible configurations (3)

   config_desc_table:
	db 09h          ; Descriptor length (9 bytes)
	db 02h          ; Descriptor type (Configuration)
	db 22h,00h      ; Total data length (34 bytes)
	db 01h          ; Interface supported (1)
	db 01h          ; Configuration value (1)
	db 00h          ; Index of string descriptor (None)
	db 40h          ; Configuration (Self powered)
	db 00h          ; Maximum power consumption (00ma)

   Interface_Descriptor:
	db 09h          ; Descriptor length (9 bytes)
	db 04h          ; Descriptor type (Interface)
	db 00h          ; Number of interface (0) 
	db 00h          ; Alternate setting (0)
	db 01h          ; Number of interface endpoints (1)
	db 03h          ; Class code ()                    
	db 00h          ; Subclass code ()                 
	db 00h          ; Protocol code ()
	db 00h          ; Index of string()       

   Class_Descriptor:
	db 09h          ; Descriptor length (9 bytes)
	db 21h          ; Descriptor type (HID)
	db 00h,01h      ; HID class release number (1.00)
	db 00h          ; Localized country code (None)
	db 01h          ; # of HID class dscrptr to follow (1)
	db 22h          ; Report descriptor type (HID)
			    ; Total length of report descriptor
;	db ffh, 00h
;	db 24h,04h		; length = 424h (1060 decimal)

;	db (end_hid_report_desc_table - hid_report_desc_table)
;	db 00h
	dwl (end_hid_report_desc_table - hid_report_desc_table)

   Endpoint_Descriptor:
	db 07h          ; Descriptor length (7 bytes)
	db 05h          ; Descriptor type (Endpoint)
	db 81h          ; Encoded address (Respond to IN, 1 endpoint)
	db 03h          ; Endpoint attribute (Interrupt transfer)
	db 08h,00h      ; Maximum packet size (8 bytes)
	db 0Ah          ; Polling interval (10 ms)

   end_config_desc_table:

;========================================================================
; These tables are the mechanism used to return status information to the
; host.  The status can be either device, interface, or endpoint.

get_dev_status_table:
        db      00h, 00h        ; remote wakeup disabled, bus powered
        db      02h, 00h        ; remote wakeup enabled, bus powered

get_interface_status_table:
        db      00h, 00h        ; always return both bytes zero

get_endpoint_status_table:
        db      00h, 00h        ; not stalled
        db      01h, 00h        ; stalled

get_configuration_status_table:
        db      00h             ; not configured
        db      01h             ; configured

get_protocol_status_table:
        db      00h             ; boot protocol
        db      01h             ; report protocol
;========================================================================

; String Descriptors
; string 0
USBStringLanguageDescription:
    db 04h          ; Length
    db 03h          ; Type (3=string)
    db 09h          ; Language:  English
    db 00h          ; Sub-language: US
;========================================================================
; These are the string descriptor implementation if they were done in ROM
;========================================================================
; string 1
USBStringDescription1:	; IManufacturerName/upsIdentManufacturer
;   db 14h          	; Length
;   db 03h          	; Type (3=string)
;   dsu "ViewSonic" 	;
; string 2
;USBStringDescription2:	; IProduct/upsIdentModel
;   db 12h          	; Length
;    db 03h          	; Type (3=string)
;    dsu "UPS-650E"  	;
;string 3
;USBStringDescription3:	; ISerialNumber/upsIdentSerialNumber
;    db 0Ah        	; Length
;    db 03h          	; Type (3=string)
;    dsu "6612"    	; If a SN is used, this must be unique
                    	; for every device or the device may
                    	; not enumerate properly
;USBStringEnd:
;========================================================================

   hid_report_desc_table:
	; UPS APPLICATION COLLECTION
	;
        db  5h, 84h                ; USAGE_PAGE (Power Device)
        db  9h,  4h                ; USAGE (UPS)
        db a1h,  1h                ; COLLECTION (Application)
	;
	; MAIN AC FLOW PHYSICAL COLLECTION
	;
        db  5h, 84h                ;   USAGE_PAGE (Power Device)
        db  9h, 1eh                ;   USAGE (Flow)
        db a1h,  0h                ;   COLLECTION (Physical)
        db 85h,  1h                ;     REPORT_ID (1)
	;
        db  9h, 1fh                ;     USAGE (FlowID)
        db 65h,  0h                ;     UNIT (None)
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h,  fh                ;     LOGICAL_MAXIMUM (15)
        db 65h,  0h                ;     UNIT (None)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	; 4-BIT PAD
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db b1h,  3h                ;     FEATURE (Cnst,Var,Abs)
	;
        db  9h, 40h                ;     USAGE (ConfigVoltage)
        db 75h,  10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;     UNIT (SI Lin:Volts)
        db 55h,  7h                ;     UNIT_EXPONENT (7)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 26h, fah,  0h           ;     LOGICAL_MAXIMUM (250)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 42h                ;     USAGE (ConfigFrequency)
        db 75h,  10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 66h,  1h, f0h           ;     UNIT (SI Lin:Hertz)
        db 55h,  0h                ;     UNIT_EXPONENT (0)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h, 3ch                ;     LOGICAL_MAXIMUM (60)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 53h                ;     USAGE (LowVoltageTransfer)
        db 75h, 10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;     UNIT (SI Lin:Volts)
        db 55h,  7h                ;     UNIT_EXPONENT (7)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 26h, fah,  0h           ;     LOGICAL_MAXIMUM (250)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 54h                ;     USAGE (HighVoltageTransfer)
        db 75h, 10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;     UNIT (SI Lin:Volts)
        db 55h,  7h                ;     UNIT_EXPONENT (7)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 26h, fah,  0h           ;     LOGICAL_MAXIMUM (250)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
	  db 09h, fdh		     ;     USAGE(iManufacturerName)
	  db 09h, feh		     ;     USAGE(iProduct)
        db 09h, ffh		     ;     USAGE(iSerialNumber)
        db 75h,  8h                ;     REPORT_SIZE (8)
        db 95h,  3h                ;     REPORT_COUNT (3)
        db 26h, ffh,  0h           ;     LOGICAL_MAXIMUM (255)
        db 65h,  0h                ;     UNIT (None)
        db b1h,  0h                ;     FEATURE (Data,Ary,Abs)
        db c0h                     ;   END_COLLECTION
	;
	; END MAIN AC FLOW PHYSICAL COLLECTION
	; OUTPUT AC FLOW PHYSICAL COLLECTION
	;
        db  5h, 84h                ;   USAGE_PAGE (Power Device)
        db  9h, 1eh                ;   USAGE (Flow)
        db a1h,  0h                ;   COLLECTION (Physical)
        db 85h,  2h                ;     REPORT_ID (2)
	;
        db  9h, 1fh                ;     USAGE (FlowID)
        db 65h,  0h                ;     UNIT (None)
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h,  fh                ;     LOGICAL_MAXIMUM (15)
        db 65h,  0h                ;     UNIT (None)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	; 4-BIT PAD
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 75h,  4h                ;     REPORT_SIZE (4)
        db b1h,  3h                ;     FEATURE (Cnst,Var,Abs)
	;
        db  9h, 40h                ;     USAGE (ConfigVoltage)
        db 75h,  10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;     UNIT (SI Lin:Volts)
        db 55h,  7h                ;     UNIT_EXPONENT (7)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 26h, fah,  0h           ;     LOGICAL_MAXIMUM (250)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 42h                ;     USAGE (ConfigFrequency)
        db 75h, 10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 66h,  1h, f0h           ;     UNIT (SI Lin:Hertz)
        db 55h,  0h                ;     UNIT_EXPONENT (0)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h, 3ch                ;     LOGICAL_MAXIMUM (60)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 43h                ;     USAGE (ConfigApparentPower)
        db 75h, 10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 66h, 21h, d1h           ;     UNIT (SI Lin:Power)
        db 55h,  7h                ;     UNIT_EXPONENT (7)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 27h, feh, ffh,  0h,  0h ;     LOGICAL_MAXIMUM (65534)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs);

        db  9h, 44h                ;     USAGE (ConfigActivePower)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 75h, 10h                ;     REPORT_SIZE (16)
        db 66h, 21h, d1h           ;     UNIT (SI Lin:Power)
        db 55h,  7h                ;     UNIT_EXPONENT (7)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 27h, feh, ffh,  0h,  0h ;     LOGICAL_MAXIMUM (65534)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 56h                ;     USAGE (DelayBeforeStartup)
        db 75h, 18h                ;     REPORT_SIZE (24)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 66h,  1h, 10h           ;     UNIT (SI Lin:Time)
        db 55h,  0h                ;     UNIT_EXPONENT (0)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 27h, feh, ffh,  0h,  0h ;     LOGICAL_MAXIMUM (65534)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 57h                ;     USAGE (DelayBeforeShutdown)
        db 75h, 18h                ;     REPORT_SIZE (24)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 66h,  1h, 10h           ;     UNIT (SI Lin:Time)
        db 55h,  0h                ;     UNIT_EXPONENT (0)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 27h, feh, ffh,  0h,  0h ;     LOGICAL_MAXIMUM (65534)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
        db c0h                     ;   END_COLLECTION
	;
	; END OUTPUT AC FLOW PHYSICAL COLLECTION

	; BATTERY SYSTEM PHYSICAL COLLECTION
	;
        db  5h, 84h                ;   USAGE_PAGE (Power Device)
        db  9h, 10h                ;   USAGE (BatterySystem)
        db a1h,  0h                ;   COLLECTION (Physical)
        db 85h,  3h                ;     REPORT_ID (3)
	;
        db  9h, 11h                ;     USAGE (BatterySystemID)
        db 65h,  0h                ;     UNIT (None)
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h,  fh                ;     LOGICAL_MAXIMUM (15)
        db 65h,  0h                ;     UNIT (None)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	; 4-BIT PAD
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db b1h,  3h                ;     FEATURE (Cnst,Var,Abs)
	;
        db  9h,  2h                ;     USAGE (PresentStatus)
        db a1h,  2h                ;     COLLECTION (Logical)
        db  9h, 6dh                ;       USAGE (Used)
        db  9h, 61h                ;       USAGE (Good)
        db 75h,  1h                ;       REPORT_SIZE (1)
        db 95h,  2h                ;       REPORT_COUNT (2)
        db 15h,  0h                ;       LOGICAL_MINIMUM (0)
        db 25h,  1h                ;       LOGICAL_MAXIMUM (1)
        db b1h,  2h                ;       FEATURE (Data,Var,Abs)
	; 6-BIT PAD
        db 75h,  6h                ;       REPORT_SIZE (6)
        db 95h,  1h                ;       REPORT_COUNT (1)
        db b1h,  3h                ;       FEATURE (Cnst,Var,Abs)
        db c0h                     ;     END_COLLECTION
	;
        db  9h, 30h                ;     USAGE (Voltage)
        db 75h, 18h                ;     REPORT_SIZE (24)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;     UNIT (SI Lin:Volts)
        db 55h,  5h                ;     UNIT_EXPONENT (5)
        db 27h, feh, ffh,  0h,  0h ;     LOGICAL_MAXIMUM (65534)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 36h                ;     USAGE (Temperature)
        db 75h, 10h                ;     REPORT_SIZE (16)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 67h,  1h,  0h,  1h,  0h ;     UNIT (SI Lin:Temperature)
        db 27h, feh, ffh,  0h,  0h ;     LOGICAL_MAXIMUM (65534)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	;
        db  9h, 58h                ;     USAGE (Test)
        db 75h,  1h                ;     REPORT_SIZE (1)
        db 95h,  6h                ;     REPORT_COUNT (6)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h,  1h                ;     LOGICAL_MAXIMUM (1)
        db 81h,  2h                ;     INPUT (Data,Var,Abs)
	; 2-BIT PAD
        db 75h,  2h                ;     REPORT_SIZE (2)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 81h,  3h                ;     INPUT (Cnst,Var,Abs)
	;
        db  9h, 58h                ;     USAGE (Test)
        db 75h,  1h                ;     REPORT_SIZE (1)
        db 95h,  4h                ;     REPORT_COUNT (4)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h,  1h                ;     LOGICAL_MAXIMUM (1)
        db b1h,  2h                ;     FEATURE (Data,Var,Abs)
	; 4-BIT PAD
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db b1h,  3h                ;     FEATURE (Cnst,Var,Abs)
        db c0h                     ;   END_COLLECTION
	;
	; END BATTERY SYSTEM PHYSICAL COLLECTION

	; POWER CONVERTER PHYSICAL COLLECTION
	;
        db  5h, 84h                ;   USAGE_PAGE (Power Device)
        db  9h, 16h                ;   USAGE (PowerConverter)
        db a1h,  0h                ;   COLLECTION (Physical)
        db 85h,  4h                ;     REPORT_ID (4)
	;
        db  9h, 17h                ;     USAGE (PowerConverterID)
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 15h,  0h                ;     LOGICAL_MINIMUM (0)
        db 25h,  fh                ;     LOGICAL_MAXIMUM (15)
        db 65h,  0h                ;     UNIT (None)
        db 81h,  2h                ;     INPUT (Data,Var,Abs)
	; 4-BIT PAD
        db 75h,  4h                ;     REPORT_SIZE (4)
        db 95h,  1h                ;     REPORT_COUNT (1)
        db 81h,  3h                ;     INPUT (Cnst,Var,Abs)
	;
	; AC INPUT PHYSICAL COLLECTION
	; 
        db  9h, 1ah                ;     USAGE (Input)
        db a1h,  0h                ;     COLLECTION (Physical)
        db  9h, 1bh                ;       USAGE (InputID)
        db  9h, 1fh                ;       USAGE (FlowID)
        db 75h,  4h                ;       REPORT_SIZE (4)
        db 95h,  2h                ;       REPORT_COUNT (2)
        db 15h,  0h                ;       LOGICAL_MINIMUM (0)
        db 25h,  fh                ;       LOGICAL_MAXIMUM (15)
        db 65h,  0h                ;       UNIT (None)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
	;
        db  9h,  2h                ;       USAGE (PresentStatus)
        db a1h,  2h                ;       COLLECTION (Logical)
        db  9h, 61h                ;         USAGE (Good)
        db 75h,  1h                ;         REPORT_SIZE (1)
        db 95h,  1h                ;         REPORT_COUNT (1)
        db 15h,  0h                ;         LOGICAL_MINIMUM (0)
        db 25h,  1h                ;         LOGICAL_MAXIMUM (1)
        db 81h,  2h                ;         INPUT (Data,Var,Abs)
	; 7-BIT PAD
        db 75h,  7h                ;         REPORT_SIZE (7)
        db 95h,  1h                ;         REPORT_COUNT (1)
        db 81h,  3h                ;         INPUT (Cnst,Var,Abs)
        db c0h                     ;       END_COLLECTION
	;
        db  9h, 30h                ;       USAGE (Voltage)
        db 75h, 10h                ;       REPORT_SIZE (16)
        db 95h,  1h                ;       REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;       UNIT (SI Lin:Volts)
        db 55h,  5h                ;       UNIT_EXPONENT (5)
        db 27h, feh, ffh,  0h,  0h ;       LOGICAL_MAXIMUM (65534)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
	;
        db  9h, 32h                ;       USAGE (Frequency)
        db 75h, 10h                ;       REPORT_SIZE (16)
        db 95h,  1h                ;       REPORT_COUNT (1)
        db 66h,  1h, f0h           ;       UNIT (SI Lin:Hertz)
        db 55h,  5h                ;       UNIT_EXPONENT (5)
        db 27h, feh, ffh,  0h,  0h ;       LOGICAL_MAXIMUM (65534)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
        db c0h                     ;     END_COLLECTION
	; 
	; END AC INPUT PHYSICAL COLLECTION

	; AC OUTPUT PHYSICAL COLLECTION
	;
        db  9h, 1ch                ;     USAGE (Output)
        db a1h,  0h                ;     COLLECTION (Physical)
        db 85h,  5h                ;       REPORT_ID (5)
	;
        db  9h, 1dh                ;       USAGE (OutputID)
        db  9h, 1fh                ;       USAGE (FlowID)
        db 75h,  4h                ;       REPORT_SIZE (4)
        db 95h,  2h                ;       REPORT_COUNT (2)
        db 15h,  0h                ;       LOGICAL_MINIMUM (0)
        db 25h,  fh                ;       LOGICAL_MAXIMUM (15)
        db 65h,  0h                ;       UNIT (None)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
	;
        db  9h, 30h                ;       USAGE (Voltage)
        db 75h, 10h                ;       REPORT_SIZE (16)
        db 95h,  1h                ;       REPORT_COUNT (1)
        db 67h, 21h, d1h, f0h,  0h ;       UNIT (SI Lin:Volts)
        db 55h,  5h                ;       UNIT_EXPONENT (5)
        db 27h, feh, ffh,  0h,  0h ;       LOGICAL_MAXIMUM (65534)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
	;
        db  9h, 32h                ;       USAGE (Frequency)
        db 75h, 10h                ;       REPORT_SIZE (16)
        db 95h,  1h                ;       REPORT_COUNT (1)
        db 66h,  1h, f0h           ;       UNIT (SI Lin:Hertz)
        db 55h,  5h                ;       UNIT_EXPONENT (5)
        db 27h, feh, ffh,  0h,  0h ;       LOGICAL_MAXIMUM (65534)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
	;
        db  9h, 35h                ;       USAGE (PercentLoad)
        db 75h,  10h                ;       REPORT_SIZE (16)
        db 95h,  1h                ;       REPORT_COUNT (1)
        db 15h,  0h                ;       LOGICAL_MINIMUM (0)
        db 26h, ffh,  0h           ;       LOGICAL_MAXIMUM (255)
        db 81h,  2h                ;       INPUT (Data,Var,Abs)
	;
        db  9h,  2h                ;       USAGE (PresentStatus)
        db a1h,  2h                ;       COLLECTION (Logical)
        db  9h, 65h                ;         USAGE (Overload)
        db  9h, 6eh                ;         USAGE (Boost)
        db  9h, 6fh                ;         USAGE (Buck)
        db 75h,  1h                ;         REPORT_SIZE (1)
        db 95h,  3h                ;         REPORT_COUNT (3)
        db 15h,  0h                ;         LOGICAL_MINIMUM (0)
        db 25h,  1h                ;         LOGICAL_MAXIMUM (1)
        db 65h,  0h                ;         UNIT (None)
        db 81h,  2h                ;         INPUT (Data,Var,Abs)
	; 5-BIT PAD
        db 75h,  5h                ;         REPORT_SIZE (5)
        db 95h,  1h                ;         REPORT_COUNT (1)
        db 81h,  3h                ;         INPUT (Cnst,Var,Abs)
        db c0h                     ;       END_COLLECTION
        db c0h                     ;     END_COLLECTION
	;
	; END AC OUTPUT PHYSICAL COLLECTION
	;
        db c0h                     ;   END_COLLECTION
	;
	; END POWER CONVERTER PHYSICAL COLLECTION

        db c0h                     ; END_COLLECTION
	;
	; END UPS APPLICATION COLLECTION

   end_hid_report_desc_table:



