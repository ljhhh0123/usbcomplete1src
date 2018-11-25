;******************************************************
;
;	file: USB Library with selftest
;	Date: July 2, 1997
;	Description:  	Selftest code modified for use with the keyboard
;			register definitions and instruction set. 
;			Ver.4 does some extra verification of USB register
;			values.
;
;			M8 BX1.1, KEYIO R2.0, ROMs B1.1
;
;		copyright 1997 Cypress Corporation
;****************************************************** 

;**************** assembler directives ***************** 

	CPU	63413

	XPAGEON

; processor registers
Port0:			equ  0h
Port1:			equ  1h
Port0Int:		equ  4h
Port1Int:		equ  5h
usb_address:		equ  10h
end0_count:		equ  11h
end0_mode:		equ  12h
end1_count:		equ  13h
end1_mode:		equ  14h
global_int:		equ  20h
endpoint_int:		equ  21h
watchdog:		equ  26h
timer_lo:		equ  24h
timer_hi:		equ  25h
control:		equ  FFh

endp1_dmabuff0:	equ  F0h
endp1_dmabuff1:	equ  F1h
endp1_dmabuff2:	equ  F2h
endp1_dmabuff3:	equ  F3h
endp1_dmabuff4:	equ  F4h
endp1_dmabuff5:	equ  F5h
endp1_dmabuff6:	equ  F6h
endp1_dmabuff7:	equ  F7h
endp0_dmabuff0:	equ  F8h
endp0_dmabuff1:	equ  F9h
endp0_dmabuff2:	equ  FAh
endp0_dmabuff3:	equ  FBh
endp0_dmabuff4:	equ  FCh
endp0_dmabuff5:	equ  FDh
endp0_dmabuff6:	equ  FEh
endp0_dmabuff7:	equ  FFh

; mode encoding
disabled:	equ  00h
nak:		equ  01h
stall:		equ  03h
ignore:		equ  04h
con_rd_ack:	equ  0Fh
con_rd_nak:	equ  0Eh
con_rd_stall:	equ  02h
con_wr_ack:	equ  0Bh
con_wr_nak:	equ  0Ah
con_wr_stall:	equ  06h
out_ack:	equ  09h
out_nak:	equ  08h
out_iso:	equ  05h
in_ack:		equ  0Dh
in_nak:		equ  0Ch
in_iso:		equ  07h

; request types
get_status:		equ  00h
clear_feature:		equ  01h
set_feature:		equ  03h
set_address:		equ  05h
get_descriptor:		equ  06h
set_descriptor: 	equ  07h
get_configuration: 	equ  08h
set_configuration: 	equ  09h
get_interface:		equ  0Ah
set_interface:		equ  0Bh
synch_frame:		equ  0Ch
device_status:		equ  00h
endpoint_status: 	equ  00h
endpoint_stalled:	equ  00h
device_remote_wakeup:	equ  01h

;descriptor types
device:			equ  01h
configuration:		equ  02h
string:			equ  03h
interface:		equ  04h
endpoint:		equ  05h
report:			equ  22h

; data memory variables
temp:			equ  11h
button_buff:		equ  12h
loop_counter:		equ  13h
bus_active:		equ  14h
suspend_port:		equ  15h
horiz_state:		equ  16h
vert_state:		equ  17h
port_temp:		equ  18h
endp1_data_toggle:	equ  19h
endp0_data_toggle: 	equ  1Ah
data_start:		equ  1Bh
data_count:		equ  1Ch
endpoint_stall:		equ  1Dh
logo_position:		equ  1Eh

;*************** interrupt vector table ****************

ORG 	00h			

jmp	reset			; reset vector		

jmp	bus_reset		; bus reset interrupt

jmp	check_input		; 128us interrupt

jmp	1ms_clear_control	; 1024ms interrupt

jmp	endpoint_zero		; endpoint 0 interrupt

jmp	endpoint_one		; endpoint 1 interrupt

jmp	error			; not implemented in this version
jmp	error			; not implemented in this version
jmp	error			; not implemented in this version
jmp	error			; not implemented in this version
jmp	error			; not implemented in this version

jmp	error			; general purpose I/0 interrupt (not enabled) 

jmp	error			; not implemented in this version

;************** program listing ************************

ORG  1Ah

error: halt

;*******************************************************
;
;	Interrupt handler: reset
;	Purpose: The program jumps to this routine when
;		 the microcontroller has a power on reset.
;
;*******************************************************

reset:
	mov A, 68h
	swap A, dsp		; sets data memory stack pointer
	mov A, 00h
	mov [logo_position], A
	mov [button_buff], A
	mov [endp1_data_toggle], A
	mov [endpoint_stalled], A
	mov [bus_active], A
	iowr Port0Int		; no ints on port 0 

	mov A, 07h		; enable bus reset, timer interrupts
	iowr global_int
	mov A, 03h		; enable endpoint interrupts
	iowr endpoint_int
	ei			; enable interrupts
wait:
	iord end1_mode
	and A, 0Fh
	cmp A, 00h		; test if configured
	jnz gpio		; if so, poll port 0
	jmp wait


;*******************************************************
;
;	Interrupt handler: bus_reset
;	Purpose: The program jumps to this routine when
;		 the microcontroller has a bus reset.
;
;*******************************************************

bus_reset:
	mov A, stall		; set to STALL INs&OUTs
	iowr end0_mode
	iord end0_mode		; check that mode was written 
	and A, 0Fh
	cmp A, 00h
	jz bus_reset

	mov A, 80h		; enable USB address = 0
	iowr usb_address
	mov A, disabled		; disable endpoint1
	iowr end1_mode
	mov A, 00h
	mov psp,a	
	jmp reset

;*******************************************************
;
;	Interrupt handler: check_input
;	Purpose: If the 128us interrupt is enabled, the 
;		program will jump to here every 128us.
;		In this program the 128us interrupt is
;		not used.
;
;*******************************************************

check_input:
	reti
	
;*******************************************************
;
;	Interrupt handler: 1ms_clear_control
;	Purpose: Every 1ms this interrupt handler clears
;		the watchdog timer.
;
;*******************************************************

1ms_clear_control:
	push A
	mov A, 41h
	iowr watchdog		; clear watchdog timer
	pop A
	reti

;*******************************************************
;
;	Interrupt handler: endpoint_zero
;	Purpose: This interrupt routine handles the specially
;		 reserved control endpoint 0 and parses setup 
;		 packets.  If a IN or OUT is received, this 
;		 handler returns to the control_read
;		 or no_data_control routines to send more data.
;
;*******************************************************

endpoint_zero:
	push A
	iord end0_mode
	and A, 80h		; check if SETUP packet received
	jz no_setup
	iord end0_mode		; check mode for valid SETUP
	and A, 9Fh
	cmp A, 91h
	jnz bad_setup
	iord end0_count		; check count for valid SETUP
	and A, CFh
	cmp A, 4Ah
	jnz bad_setup
	call host2dev_devrecip	; SETUP ...goto parsing 
no_setup:
	pop A
	reti			; IN or OUT, or SETUP completed
bad_setup:
	mov A,03h		; stall following an bad SETUP
	iowr end0_mode
	jmp no_setup

;*************stage one..determine type of transfer (bmRequestType)

host2dev_devrecip:
	mov A, nak		; clear the setup flag leave in Nak mode
	iowr end0_mode
	iord end0_mode		; retry write if needed
	cmp A, nak
	jnz host2dev_devrecip

	mov A, [endp0_dmabuff0]	; parse packet
	cmp A, 00h
	jnz host2dev_intrecip

	mov A, [endp0_dmabuff1]
	cmp A, clear_feature
	jz clear_feat

	mov A, [endp0_dmabuff1]
	cmp A, set_feature
	jz set_feat

	mov A, [endp0_dmabuff1]
	cmp A, set_address
	jz set_addr

	mov A, [endp0_dmabuff1]
	cmp A, set_configuration
	jz set_config

h2dd_stall:
	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	iord end0_mode		; write retry
	cmp A, stall	
	jnz h2dd_stall
	ret

host2dev_intrecip:
	mov A, [endp0_dmabuff0]
	cmp A, 01h
	jnz host2dev_endprecip

	mov A, [endp0_dmabuff1]	; parse packet
	cmp A, set_interface
	jz set_interf

h2di_stall:
	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	iord end0_mode		; write retry
	cmp A, stall	
	jnz h2di_stall
	ret

host2dev_endprecip:
	mov A, [endp0_dmabuff0]
	cmp A, 02h
	jnz dev2host_devrecip

	mov A, [endp0_dmabuff1]	; parse
	cmp A, set_feature
	jz set_feat

	cmp A, clear_feature
	jz clear_feat

	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	ret
	
dev2host_devrecip:
	mov A, [endp0_dmabuff0]	; read the first byte of the buffer
	cmp A, 80h		; compare to 80h
	jnz dev2host_intrecip

	mov A, [endp0_dmabuff1]	; parse
	cmp A, get_configuration
	jz get_config
	
	mov A, [endp0_dmabuff1]
	cmp A, get_status
	jz get_stat

	mov A, [endp0_dmabuff1]
	cmp A, get_descriptor
	jz get_desc

	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	ret

dev2host_intrecip:
	mov A, [endp0_dmabuff0]
	cmp A, 81h
	jnz dev2host_endprecip

	mov A, [endp0_dmabuff1]	; parse
	cmp A, get_interface
	jz get_interf	

	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	ret

dev2host_endprecip:
	mov A, [endp0_dmabuff0]
	cmp A, 82h
	jz match
	ret
  match:
	mov A, [endp0_dmabuff1]	; get HID class descriptor
	cmp A, get_descriptor
	jz get_desc

	mov A, [endp0_dmabuff1]	; parse
	cmp A, endpoint_status
	jz endp_status

	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	ret


;************stage two..determine request type (bRequest)



set_addr:
	call no_data_control
	mov A, [endp0_dmabuff2]		; get address
	or A, 80h				; address enable bit
	iowr usb_address		; set usb address register
	ret

set_feat:
	mov A, [endp0_dmabuff2]
	cmp A, endpoint_stalled
	jnz remote_wakeup
	mov A, 01h
	mov [endpoint_stall], A
	call no_data_control	
	ret
	remote_wakeup:
	call no_data_control
	ret

clear_feat:
	mov A, [endp0_dmabuff2]
	cmp A, endpoint_stalled
	jnz not_endp_clear 
	mov A, 00h
	mov [endpoint_stall], A
	not_endp_clear:
	call no_data_control
	ret

get_interf:
	mov A, 69h
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read
	ret

set_interf:
	call no_data_control
	ret

get_config:
	mov A, 68h
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A	 
	call control_read
	ret

set_config:
	call no_data_control
	ret

get_stat:
	mov A, [endp0_dmabuff7]
	cmp A, device_status
	jz dev_status

	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	ret

endp_status:
	mov A, [endpoint_stall]
	cmp A, endpoint_stalled
	jnz endp_stalled_status
	mov A, 6Ah
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read
	ret
	endp_stalled_status:
	mov A, 6Ch
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read
	ret

get_desc:
	mov A, [endp0_dmabuff3]
	cmp A, device
	jz device_desc

	mov A, [endp0_dmabuff3]
	cmp A, configuration
	jz config_desc

	mov A, [endp0_dmabuff3]
	cmp A, report
	jz hid_report_descriptor

	mov A, stall		; send a stall to indicate that the requested
	iowr end0_mode		; function is not supported
	ret
 
;***********stage three..determine descriptor type (descriptor)

dev_status:
	mov A, 66h
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read
	ret

device_desc:
	mov A, 00h
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read
	ret

config_desc:
	mov A, 12h
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read
	ret

hid_report_descriptor:
	mov A, 34h
	mov [data_start], A
	mov A, [endp0_dmabuff6]
	mov [data_count], A
	call control_read

	;******** get ready for endpoint 1!!!!! *********

	mov A, 00h		; clear movement
	mov [endp1_dmabuff1], A	; registers
	mov A, 00h		; so mouse doesn't move
	mov [endp1_dmabuff2], A	; on plug-in

	mov A, in_ack		; respond to IN on endpoint 1, enable, 3 bytes
	iowr end1_mode
	mov A, 03h
	iowr end1_count

	ret			

;*******************************************************
;
;	Interrupt handler: endpoint_one
;	Purpose: This interrupt routine handles the specially
;		 reserved data endpoint 1 (for a mouse).  This
;		 interrupt happens every time a host sends an
;		 IN on endpoint 1.  The data to send (NAK or 3
;		 byte packet) is already loaded, so this routine
;		 just prepares the dma buffers for the next packet
;
;*******************************************************

endpoint_one:
	push A				; store A register

	iord end1_mode
	cmp a, 16 + in_nak		; ACK,in_nak mode
	jnz error
	mov A, [endp1_data_toggle]	; change endpoint 1
	xor A, 80h			; data toggle
	and A, 80h
	mov [endp1_data_toggle], A


	mov A, 00h			; clear data from the dma buffer
	mov [endp1_dmabuff0], A
	mov [endp1_dmabuff1], A
	mov [endp1_dmabuff2], A


	pop A				; restore A register

	reti
	
;*******************************************************
;
;	Function: gpio
;
;	Purpose: moves mouse cursor in "USB" pattern
;
;*******************************************************

gpio:

	mov A, [logo_position]		; get x displacement
	index usb_table
	mov [endp1_dmabuff1], A

	inc [logo_position]	

	mov A, [logo_position]		; get y displacement
	index usb_table
	mov [endp1_dmabuff2], A

	inc [logo_position]	
	
	mov A, in_ack
	iowr end1_mode
	mov A, 03h
	or A, [endp1_data_toggle]
	iowr end1_count


	mov A, [logo_position]
	cmp A, 6Eh    			;compare to 110
	jnz wait_mouse_data_sent

	reset_usb_table:		; reset table if at end
	mov A, 00h
	mov [logo_position], A

;@@@stop responding to host, check if re-enumerated
iowr end1_mode
iowr usb_address
	
   wait_mouse_data_sent:
	iord usb_address	; if address = 0 a bus reset has occured
	cmp A,80h			; jump to wait loop
	jz wait
					; wait for data to be sent 
	iord end1_mode			; before loading registers
	and A, 01h			; again
	jnz wait_mouse_data_sent

	jmp gpio

;**********USB library main routines*******************


;******************************************************
;
;	function:  Control_read
;	Purpose:   Performs the control read operation
;		   as defined by the USB specification
;	SETUP-IN-IN-IN...OUT
;
;	data_start: must be set to the descriptors info
;		    as an offset from the beginning of the
;		    control_read_table
;	data_count: must be set to the size of the 
;		    descriptor 
;******************************************************

control_read: 

	mov X, 00h
	mov A, 00h
	mov [endp0_data_toggle], A
cr_wr:
	mov A, nak			;clear PID bits, leave in nak mode
	iowr end0_mode
	iord end0_mode
	cmp A, nak
	jnz cr_wr

   control_read_data_stage:
	mov X, 00h
	mov A, 00h
	mov [loop_counter], A	
crds_wr:
	mov A, con_rd_nak		;clear PID bits, leave in nak mode
	iowr end0_mode	
	iord end0_mode
	cmp A, con_rd_nak
	jnz crds_wr

	mov A, [data_count]
	cmp A, 00h
	jz control_read_status_stage

      dma_load_loop:			; loop to load data into the data buffer
	mov A, [data_start]
	index control_read_table
	mov [X + endp0_dmabuff0], A	; load dma buffer
	inc [data_start]
	inc X
	inc [loop_counter]
	dec [data_count]		; exit if descriptor
	jz dma_load_done		; is done
	mov A, [loop_counter]		; or 8 bytes sent
	cmp A, 08h
	jnz dma_load_loop

      dma_load_done:

	iord end0_count
	mov A, [endp0_data_toggle]
	xor A, 80h
	mov [endp0_data_toggle], A
	or A, [loop_counter]
	iowr end0_count

cr_wr_ack:
	mov A, con_rd_ack
	iowr end0_mode
	iord end0_mode
	and A, 0Fh
	cmp A, con_rd_ack
	jnz cr_wr_ack

      wait_control_read:
	iord end0_mode			; wait for the data to be
	and A, 01h     		        ; transfered
	jz control_read_data_stage
	iord end0_mode
    	and A, A0h             	 	; check if out/setup was sent by host
	jnz control_read_status_stage
	jmp wait_control_read

	jmp control_read_data_stage

   control_read_status_stage:		; OUT at end of data transfer
	ret

;******************************************************
;
;	function: control_write
;	purpose:  performs the control write operaion
;		  as defined by the USB specification
;	SETUP-OUT-OUT-OUT...IN
;******************************************************

control_write:

; not implemented with a mouse, but may be needed for
; other devices

	ret

;******************************************************
;
;	function: no_data_control
;	purpose: performs the no-data control operation
;		 as defined by the USB specification
;	SETUP-IN
;******************************************************

no_data_control:

	mov A, con_wr_stall	; setup for status stage IN
	iowr end0_mode
	iord end0_mode
	cmp A,con_wr_stall
	jnz no_data_control

  wait_nodata_sent:
	iord end0_mode 		; wait for the IN to be
	and A, 40h		; transfered
	jz wait_nodata_sent

	ret


;*********************************************************
;                   rom lookup tables
;*********************************************************

control_read_table:
   device_desc_table:
	db	12h		; size of descriptor (18 bytes)
	db	01h		; descriptor type (device descriptor)
	db	00h, 01h	; USB spec release (ver 1.0)
	db	00h		; class code (each interface specifies class information)
	db	00h		; device sub-class (must be set to 0 because class code is 0)
	db	00h		; device protocol (no class specific protocol)
	db	08h		; maximum packet size (8 bytes)
	db	5Eh, 04h	; vendor ID (note Microsoft vendor ID)
	db	11h, 11h	; product ID (Microsoft USB mouse product ID)
	db	14h, 00h	; device release number 
	db	00h		; index of manufacturer string (not supported)
	db	00h		; index of product string (not supported)
	db	00h		; index of serial number string (not supported)
	db	01h		; number of configurations (1)
   config_desc_table:
	db	09h		; length of descriptor (9 bytes)
	db	02h		; descriptor type (CONFIGURATION)
	db	22h, 00h	; total length of descriptor (34 bytes)
	db	01h		; number of interfaces to configure (1)
	db	01h		; configuration value (1)
	db	00h		; configuration string index (not supported)
	db	80h		; configuration attributes (bus powered...or will be in future
	db	32h		; maximum power (100mA)
	db	09h		; length of descriptor (9 bytes)
	db	04h		; descriptor type (INTERFACE)
	db	00h		; interface number (0)
	db	00h		; alternate setting (0)
	db	01h		; number of endpoints (1)
	db	03h		; interface class (3..defined by USB spec)
	db	01h		; interface sub-class (1..defined by USB spec)
	db	02h		; interface protocol (2..defined by USB spec)
	db	00h		; interface string index (not supported)
	db	07h		; descriptor length (7 bytes)
	db	05h		; descriptor type (ENDPOINT)
	db	81h		; endpoint address (IN endpoint, endpoint 1)
	db	03h		; endpoint attributes (interrupt)
	db	03h, 00h	; maximum packet size (3 bytes)
	db	0Ah		; polling interval (10ms)
	db	09h		; descriptor size (9 bytes)
	db	21h		; descriptor type (HID)
	db	00h, 01h	; class specification (1.00)	
	db	00h		; hardware target country (US)
	db	01h		; number of HID class descriptors to follow (1)
	db	22h		; report descriptor type (HID)
	db	32h, 00h	; total length of report descriptor			; 
   hid_report_desc_table:
	db	05h, 01h	; usage page (generic desktop)
	db	09h, 02h	; usage (mouse)
	db	A1h, 01h	; collection (application)
	db	09h, 01h	; usage (pointer)
	db	A1h, 00h	; collection (linked)
	db	05h, 09h	; usage page (buttons)
	db	19h, 01h	; usage minimum (1)
	db	29h, 03h	; usage maximum (3)
	db	15h, 00h	; logical minimum (0)
	db	25h, 01h	; logical maximum (1)
	db	95h, 03h	; report count (3 bytes)
	db	75h, 01h	; report size (1)
	db	81h, 02h	; input (3 button bits)
	db	95h, 01h	; report count (1)
	db	75h, 05h	; report size (5)
	db	81h, 01h	; input (constant 5 bit padding)
	db	05h, 01h	; usage page (generic desktop)
	db	09h, 30h	; usage (X)
	db	09h, 31h	; usage (Y)
	db	15h, 81h	; logical minimum (-127)
	db	25h, 7Fh	; logical maximum (127)
	db	75h, 08h	; report size (8)
	db	95h, 02h	; report count (2)
	db	81h, 06h	; input (2 position bytes X & Y)
	db	C0h, C0h	; end collection, end collection
   get_dev_status_table:
	db	00h, 00h	; bus powered, no remote wakeup
   get_config_table:
	db	01h		; configuration 1
   get_interface_table:
	db	00h		; interface 0
   get_endp_status_table:
	db	00h, 00h	; endpoint not stalled
   get_endp_stalled_status_table:
	db	01h, 00h	; endpoint stalled

;************************
   usb_table:

;	    x    y
;---------------------------
	db 00h, 05h	;1
	db 00h, 05h	;2
	db 00h, 05h	;3
	db 00h, 05h	;4
	db 00h, 05h	;5
	db 05h, 05h	;6
	db 05h, 00h	;7
	db 05h, 00h	;8
	db 05h, FBh	;9
	db 00h, FBh	;10
	db 00h, FBh	;11
	db 00h, FBh	;12
	db 00h, FBh	;13
	db 00h, FBh	;14
	db 23h, 05h	;15
	db FBh, FBh	;16
	db FBh, 00h	;17
	db FBh, 00h	;18
	db FBh, 05h	;19
	db 00h, 05h	;20
	db 05h, 05h	;21
	db 05h, 00h	;22
	db 05h, 00h	;23
	db 05h, 05h	;24
	db 00h, 05h	;25
	db FBh, 05h	;26
	db FBh, 00h	;27
	db FBh, 00h	;28
	db FBh, FBh	;29
	db 05h, 05h	;30
	db 1Eh, 00h	;31
	db 05h, 00h	;32
	db 05h, 00h	;33
	db 05h, 00h	;34
	db 05h, FBh	;35
	db 00h, FBh	;36
	db FBh, FBh	;37
	db FBh, 00h	;38
	db FBh, 00h	;39
	db FBh, 00h	;40
	db 0Fh, 00h	;41
	db 05h, FBh	;42
	db 00h, FBh	;43
	db FBh, FBh	;44
	db FBh, 00h	;45
	db FBh, 00h	;46
	db FBh, 00h	;47
	db 00h, 05h	;48
	db 00h, 05h	;49
	db 00h, 05h	;50
	db 00h, 05h	;51
	db 00h, 05h	;52
	db 00h, 05h	;53
	db 00h, E2h	;54
	db BAh, 00h	;55

