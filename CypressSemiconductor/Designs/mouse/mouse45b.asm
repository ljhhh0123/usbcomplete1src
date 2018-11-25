;***********************************************************************
;				Cypress Semiconductor
; 			Mouse Demonstration Design Kit Firmware 
;
; Features :
; Three button mouse
; Passes Chapter 9 and Hidview Tests 
; Includes Suspend/Resume Feature
; Includes Remote Wakeup Feature
;
; This firmware file is for demonstration purposes only.  
; Cypress Semiconductor will not assume any liability for its use.
;=======================================================================
; 5/29/98	wmh	v4.5b	Made another copy of the mouse firmware
; This version is HID Draft4 compliant (Won't work with OSR2.1)
; Differences between HID Draft3 and Draft4 compliance is only in the order
; in which the class and endpoint descriptors are sent to the host.
; Draft3 : Endpoint first then Class
; Draft4 : Class first then Endpoint
; This means that the only differences will be in the ROM lookup table
; and the GetHIDDescriptor request in the USB_EP0_ISR
;=======================================================================
; 03/10/98	lxa   v4.5	Modified control_read routines
; control_read and control_read2 did not properly handle the case where
; the total number of data bytes to send was a multiple of 8.  In this
; case, the transmission has to send a zero-length data packet to 
; terminate the data stage.
;=======================================================================
; 02/03/98	lxa	v4.4 	Change in USB_EP0_ISR
; GetStringdescriptor sends string report descriptor.
; Added string descriptors in the ROM lookup table.
;=======================================================================
; 01/06/98	lxa	v4.3	Added some new routines. 
; Added GetIdle, SetIdle and GetReport.
; Added execute2 and control_read2 to be able to send data from
; a RAM buffer.
;=======================================================================
; 01/08/98	wmh	v4.2	Remote Wakeup bug Fix
; Wakeup_ISR changed so that we force J state then clear it before 
; doing a Force Resume
;=======================================================================
; 12/01/97	wmh	v4.1	Exchanged Endpoint and Class Descriptors in the 
; ROM lookup table so that Endpoint comes before Class
; Change in GetHIDDescriptor to accomodate this.
;=======================================================================
; 11/11/97	wmh	v4.0	Change in main, ReadButtons and One_msec
; Debouncing the buttons + drag solution
;=======================================================================
; 11/7/97	wmh	v3.9	Change in main, ReadButtons, CheckHorizontal
; and CheckVertical to solve count loss in movement
;=======================================================================
; 10/13/97	wmh	v3.8	Change in USB_EP0_ISR
; SetConfiguration request was changed so as to enable endpoint 1
; GetReport is stalled
; GetReportDescriptor sends HID Report Descriptor
;========================================================================
; 9/26/97	wmh 	v3.7 small changes
; One_mSec_ISR and Reset have been changed
;========================================================================
; 8/29/97	wmh 	v3.5	Remote Wake function added
; Remote Wakeup interrupt has been added (Wakeup_ISR)
; The One_mSec_ISR has been changed to accomodate remote wakeup
;========================================================================
; 8/21/97   wmh   v2.4.4 control read correction (Endpoint_0 ISR)
; Fixes the case where the host resends a setup packet
;========================================================================
; 7/9/97	wmh	v2.4.3 add features
; Turning the LED's off and on has been added to the suspend/Resume
; subroutine in the One_mSec_ISR
;========================================================================
; 7/3/97	wmh	v2.4.2 add features
; Suspend/Resume features have been added
; Main work done in the One_mSec_ISR
;========================================================================
; 6/25/97	wmh	v2.1 add features
; changes to allow the code to pass chapter 9 and hidview tests have been
; done.  That meant major rework of the endpoint zero interrupt service
; routine (USB_EP0_ISR).
;========================================================================
; 5/15/97	gwg	v1.1 minor corrections
; I made a couple of changes to the control_read routine.  I deleted the
; redundant I/O write to clear the setup bit in the USB_EP0_RX_Status
; before the "control_read_data_stage".
;
; I also removed an unused jmp after the "wait_control_read" loop that
; could never be executed.
;=======================================================
; 4/28/97	gwg	v1.0 major rewrite
; The mouse code still needs support for suspend and 
; remote wakeup.
;**************** assembler directives ***************** 
label:          XPAGEON
		
; I/O ports
Port0_Data:            equ     00h      ; GPIO data port 0
Port1_Data:            equ     01h      ; GPIO data port 1
Port0_Interrupt:       equ     04h      ; Interrupt enable for port 0
Port1_Interrupt:       equ     05h      ; Interrupt enable for port 1
Port0_Pullup:          equ     08h      ; Pullup resistor control for port 0
Port1_Pullup:          equ     09h      ; Pullup resistor control for port 1

; USB ports
USB_EP0_TX_Config:      equ     10h     ; USB EP0 transmit configuration
USB_EP1_TX_Config:      equ     11h     ; USB EP1 transmit configuration
USB_Device_Address:     equ     12h     ; USB device address assigned by host
USB_Status_Control:     equ     13h     ; USB status and control register
USB_EP0_RX_Status:      equ     14h     ; USB EP0 receive status

; control ports
Global_Interrupt:       equ     20h     ; Global interrupt enable
Watchdog:               equ     21h     ; clear watchdog Timer
Cext:				equ 	  22h	    ; Cext register
Timer:                  equ     23h     ; free-running Timer

; GPIO Isink registers
Port0_Isink:            equ     30h
Port0_Isink0:           equ     30h
Port0_Isink1:           equ     31h
Port0_Isink2:           equ     32h
Port0_Isink3:           equ     33h
Port0_Isink4:           equ     34h
Port0_Isink5:           equ     35h
Port0_Isink6:           equ     36h
Port0_Isink7:           equ     37h

Port1_Isink:            equ     38h
Port1_Isink0:           equ     38h
Port1_Isink1:           equ     39h
Port1_Isink2:           equ     3Ah
Port1_Isink3:           equ     3Bh

; control port
Status_Control:         equ     FFh	; Processor Status and Control

;**********  Register constants  ************************************
; Processor Status and Control
RunBit:			equ	 1h		; CPU Run bit
SuspendBits:		equ    9h		; Run and suspend bits set
PowerOnReset:		equ   10h		; Power on reset bit
USBReset:			equ	20h		; USB Bus Reset bit
WatchDogReset:		equ	40h		; Watchdog Reset bit

; USB Status and Control
BusActivity:		equ	 1h		; USB bus activity bit
ForceResume:		equ	 3h		; force resume to host

; interrupt masks
TIMER_ONLY:			equ	 4h		; one msec timer

ENUMERATE_MASK:		equ	0Ch		; one msec timer 	
							; USB EP0 interrupt

RUNTIME_MASK:		equ   1Ch     	; one msec timer
							; USB EP0 interrupt
							; USB EP1 interrupt

WAKEUP_MASK:		equ	80h		; Cext wakeup interrupt

; USB EP1 transmit configuration
DataToggle:		equ	40h			; Data 0/1 bit

; Phototransistor and LED current values
Ptr_Current: 	equ 	07h			; port0 current setting for PTR
LED_Current: 	equ 	0fh			; port1 current setting for LED

; The procedure to set or choose the PTR and LED current values is :
;  1) Program test chip with values shown above.
;  2) Insert into board with typical LED and PTRs.
;  3) Plug into USB computer to activate mouse. 
;  4) Using an oscilloscope on the GPIO Port 0 pins, spin
;     the mouse wheel. Observe transitions on PTR pins. Signal
;     should swing full scale, with ~50% duty cycle when the 
;     wheel is moving.
;  5) If signal is "High" for > 50% of the time when wheel is
;     moving, reduce the LED_Current value and repeat from step
;     1. If the signal is "Low" for > 50% of the time, increase
;     the LED_Current value and repeat. (Alternately, Ptr_Current
;     could increased / decreased.)
;  6) Settings are proper when duty cycle is approximately 50% 
;     on all pins.


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
setup:          	equ  B4h
in:             	equ  96h
out:            	equ  87h
data0:          	equ  C3h
data1:          	equ  D2h
ack:            	equ  4Bh
nak:            	equ  5Ah

DISABLE_REMOTE_WAKEUP:  equ   0         ; bit[1] = 0
ENABLE_REMOTE_WAKEUP:   equ   2         ; bit[1] = 1

BOOT_PROTOCOL:		equ	0		; bit[0] = 0
REPORT_PROTOCOL:		equ	1		; bit[0] = 1

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
button_position:		equ  78h
horiz_position:        	equ  79h
vert_position:         	equ  7Ah

;------------------------------------------------------------------------
; data memory variables
; To support the USB specification.
;------------------------------------------------------------------------
interrupt_mask:		equ  20h
port_temp:			equ  21h
endp0_data_toggle: 	equ  22h
loop_counter:		equ  23h
horiz_state:		equ  24h
vert_state:			equ  25h
data_start:			equ  26h
data_count:			equ  27h
endpoint_stall:		equ  28h

remote_wakeup_status:   equ  29h        	; remote wakeup request
							; zero is disabled
							; two is enabled
configuration_status:   equ  2Ah        	; configuration status
							; zero is unconfigured
							; one is configured
;idle_status:           equ  2Bh        	; support SetIdle and GetIdle
protocol_status:      	equ  2Ch        	; zero is boot protocol
							; one is report protocol
suspend_counter:		equ  2Dh		; contains number of idle bus msecs 
wakeup_counter: 		equ  2Eh		; used for 10msec count by Wakeup 
wakeup_flag:		equ  2Fh		; used to indicate wakeup process 
disch_counter:		equ  30h		; used to discharge the capacitor
report_buffer:		equ  31h          ; used by GetReport
                                          ; order must be buttons,horizontal,vertical
buttons:			equ  31h		
horizontal:			equ  32h		
vertical:			equ  33h
button_flag:		equ  34h
button1_deb:		equ  35h		; debouncing register 
new_idle_period:        equ  36h          ; used for idle period(ms)
prev_idle_period:       equ  37h          ; used to save the previous idle period
idle_period:            equ  38h  
idle_period_counter:    equ  39h
4ms_counter:            equ  40h          ; used to count 4ms in 1 ms routine
new_idle_flag:          equ  41h          ; used to signal a new idle period

;*************** interrupt vector table ****************

ORG 	00h			

jmp	Reset				; reset vector		

jmp	DoNothing_ISR		; 128us interrupt

jmp	One_mSec_ISR		; 1024ms interrupt

jmp	USB_EP0_ISR  		; endpoint 0 interrupt

jmp	USB_EP1_ISR 		; endpoint 1 interrupt

jmp	Reset				; reserved interrupt

jmp	DoNothing_ISR		; general purpose I/0 interrupt

jmp	Wakeup_ISR			; wakeup or resume interrupt


;************** program listing ************************

ORG  10h
;*******************************************************
; The 128 uSec interrupt is not used by the mouse code.
; If this interrupt occurs, do nothing except re-enable
; interrupts.
; The GPIO interrupts are not used in this version of
; the firmware.
; The Wakeup interupt is not used, either in this version.
DoNothing_ISR:
	push A
  	mov A, [interrupt_mask]
	ipret Global_Interrupt
	
;*******************************************************
; The Wakeup interrupt is used to force the host to 
; resume due to a mouse movement or a button press
Wakeup_ISR:
	push A
	mov A, 0h					; clear Cext ( Discharge Capacitor )
	iowr Cext
	mov A, 0f0h					; turn on the phototransistors
	iowr Port0_Data			
	mov A, 0feh             		; turn on the LED on Port 1 bit[0]
	iowr Port1_Data
	mov A, FFh
	mov [disch_counter], A
delay2:
	dec A
	jnz delay2
	iowr Watchdog				; clear watchdog timer
	mov A, FFh
	dec [disch_counter]
	jnz delay2

	iord Port0_Data				; read port 0
	cmp A, [port_temp]			; compare port 0 data to previosly stored data
	jz No_change
	iord USB_Status_Control			; check if there is no bus activity
	and A, BusActivity
	jnz Wakeup_end				; bus active
	iord USB_Status_Control			; set J state
	or A, 04h					; 
	iowr USB_Status_Control
	and A, 0fBh					; clear J state
	iowr USB_Status_Control
	iord USB_Status_Control			; send wakeup to host
	or A, ForceResume				; set Force Resume bit
	iowr USB_Status_Control
	mov A, 01h					; set wakeup flag
	mov [wakeup_flag], A
	mov A, 0h					; clear wakeup counter
	mov [wakeup_counter], A
	mov A, TIMER_ONLY				; enable one msec timer interrupts
	iowr Global_Interrupt
Wakeup_wait:
	mov A, [wakeup_counter]			; Wait for 10ms
	cmp A, 0Ah
	jc Wakeup_wait
	mov A, 0h					; disable interrupts
	iowr Global_Interrupt		
	iord USB_Status_Control			; Clear Force Resume bit 
	and A, ~ForceResume					
	iowr USB_Status_Control
	mov A, 0h					; clear wakeup flag
	mov [wakeup_flag], A
	iord Port0_Data				; read port 0
	mov [port_temp], A			; save value
No_change:
      mov A, 0ffh             		; turn off the LED on Port 1 bit[0]
	iowr Port1_Data	
	mov A, 01h					; disable open drain O/P driver
	iowr Cext					; start charging for the next one
Wakeup_end:
	mov A, WAKEUP_MASK
	ipret Global_Interrupt

;*******************************************************
; The 1 msec interrupt is only used to clear the watchdog 
; timer.  This interrupt service routine would be the
; place to enter suspend mode.
One_mSec_ISR:
	push A
	iowr Watchdog				; clear watchdog timer
 
	dec [4ms_counter]                   ; count til 4 to increment
      jnz button_debounce
      mov A,[idle_period_counter]
      cmp A, 0ffh                         ; if 0ffH is reach in the 
      jz 4ms_set                          ; idle_period_counter no more
      inc [idle_period_counter]           ; increment
4ms_set:
      mov A,4
      mov [4ms_counter],A

button_debounce:
	mov A, [button1_deb]
	cmp A, 0h
	jz no_debounce
	inc A
	mov [button1_deb], A
	cmp A, 30
	jnz no_debounce
	mov A, 0h
	mov [button1_deb], A	
no_debounce:
	mov A, [wakeup_flag]			; check if we are in a remote wakeup process
	cmp A, 01h
	jnz notremote_wakeup
	inc [wakeup_counter]			; increment wakeup counter
	mov A, TIMER_ONLY				; enable One_msec_ISR
	ipret Global_Interrupt
notremote_wakeup:
	iord USB_Status_Control			; check if there is no bus activity
	and A, BusActivity
	jz Inc_counter				; no bus activity
	iord USB_Status_Control			; clear the bus activity bit
	and A, ~BusActivity
	iowr USB_Status_Control
	mov A, 3h					; clear the suspend counter
	mov [suspend_counter], A
	jmp One_mSec_end
Inc_counter:
	dec [suspend_counter]			; check if 3msecs of bus inactivity passed
	jnz One_mSec_end				; less than 3msecs
	iord Port0_Data				; save current value
	mov [port_temp], A

	mov A, 3h					; clear the suspend counter
	mov [suspend_counter], A
      mov A, 0ffh             		; turn off the LED on Port 1 bit[0]
	iowr Port1_Data
	iowr Port0_Data
	mov A, [remote_wakeup_status]		; check if remote wakeup is enabled 
	cmp A, ENABLE_REMOTE_WAKEUP
	jnz Suspend1				; Not enabled
	
	mov A, 0
	iowr Cext
	mov A, FFh
	mov [disch_counter], A
delay:
	dec A
	jnz delay
	iowr Watchdog				; clear watchdog timer
	mov A, FFh
	dec [disch_counter]
	jnz delay

	mov A, 01h					
	iowr Cext					; start charging external capacitor
	mov A, WAKEUP_MASK			; wakeup is the ONLY interrupt enabled
	iowr Global_Interrupt
Suspend1:
	iord Status_Control			;set the suspend bit causing suspend
	or A, SuspendBits
	iowr Status_Control
	nop
	mov A, 0f0h					; turn on the phototransistors
	iowr Port0_Data	
	mov A, 0feh             		; turn on the LED on Port 1 bit[0]
	iowr Port1_Data	
One_mSec_end:
	mov A, [interrupt_mask]
	ipret Global_Interrupt

;*******************************************************
;	Interrupt handler: endpoint_one
;	Purpose: This interrupt routine handles the specially
;		 reserved data endpoint 1 (for a mouse).  This
;		 interrupt happens every time a host sends an
;		 IN on endpoint 1.  The data to send (NAK or 3
;		 byte packet) is already loaded, so this routine
;		 just prepares the dma buffers for the next packet
USB_EP1_ISR:
	push A				; save accumulator on stack

	iord USB_EP1_TX_Config		; return NAK when data is not
	and A, 7Fh				; ready
	xor A, DataToggle			; flip data 0/1 bit
	iowr USB_EP1_TX_Config

	mov A, 0h
	mov [horiz_position], A	
	mov [vert_position], A	
	mov [button_position], A	

	mov A, [interrupt_mask]		; return from interrupt
	ipret Global_Interrupt

;*******************************************************
; reset processing
; The idea is to put the microcontroller in a known state.  As this
; is the entry point for the "reserved" interrupt vector, we may not
; assume the processor has actually been reset and must write to all
; of the I/O ports.
;
;	Port 0 bits 3:0 are the phototransistors
;		Write these pins "low" with midrange current to bias 
;		the phototransistors.
;	Port 0 bits 7:4 are the mouse buttons
;		Write these pins "high" with pullup resistors to 
;		support the mouse buttons.
;	Port 1 bit 0 is the LED output
;		Write this pin low with maximum current sink to turn
;		on the LEDs.
Reset:
	mov A, endpoint_0	; move data stack pointer
	swap A, dsp		; so it does not write over USB fifos
;
; initialize Port 0
;
	mov A, Ptr_Current		; select midrange DAC setting
	iowr Port0_Isink0			; isink current Port 0 bit[0]
	iowr Port0_Isink1			; isink current Port 0 bit[1]
	iowr Port0_Isink2			; isink current Port 0 bit[2]
	iowr Port0_Isink3			; isink current Port 0 bit[3]

	mov A, 0				; select minimum DAC setting
	iowr Port0_Isink4			; isink current Port 0 bit[4]
	iowr Port0_Isink5			; isink current Port 0 bit[5]
	iowr Port0_Isink6			; isink current Port 0 bit[6]
	iowr Port0_Isink7			; isink current Port 0 bit[7]

	mov A, 0fh				; disable Port 0 bit[3:0] pullups
	iowr Port0_Pullup			; enable  Port 0 bit[7:4] pullups

	mov A, 0f0h				; initialize Port 0 data
	iowr Port0_Data			; output zeros to Port 0 bit[3:0]
						; output ones  to Port 0 bit[7:4]
	mov [port_temp], A

;
; initialize Port 1
;
	mov A, LED_Current		; select maximum DAC setting
	iowr Port1_Isink0			; isink current Port 1 bit[0]
	iowr Port1_Isink1			; isink current Port 1 bit[1]
	iowr Port1_Isink2			; isink current Port 1 bit[2]
	iowr Port1_Isink3			; isink current Port 1 bit[3]

	mov A, 0h				; enable Port 1 bit [7:0] pullups
	iowr Port1_Pullup	
	
      mov A, 0feh             	; turn on the LED on Port 1 bit[0]
	iowr Port1_Data	

	mov A, 0		
	iowr Port0_Interrupt		; disable port 0 interrupts  
	iowr Port1_Interrupt		; disable port 1 interrupts
	iowr Cext
;
; initialize variables
;
	mov [buttons], A			; no buttons pushed
	mov [horiz_state], A		; clear the horizontal state
	mov [horizontal], A		; clear horizontal count
	mov [vert_state], A		; clear the vertical state
	mov [vertical], A			; clear vertical count
	mov [endpoint_stall], A
	mov [remote_wakeup_status], A
	mov [configuration_status], A
	mov [wakeup_counter], A
	mov [wakeup_flag], A
	mov [disch_counter], A
	mov [horiz_position], A
	mov [vert_position], A
	mov [button_position], A
	mov [button_flag], A
	mov [button1_deb], A
      mov [idle_period], A
      mov [prev_idle_period], A
	mov [new_idle_period], A
	mov [new_idle_flag], A
      mov [idle_period_counter], A
	mov A,3				; initialize suspend counter
	mov [suspend_counter], A	; 3 msec idle, suspend

      mov A,4				; initialize  4ms_counter to 4
	mov [4ms_counter], A     	; 

	iowr Watchdog			; clear watchdog timer
;	mov A, ENABLE_REMOTE_WAKEUP	; **** debug only ****
;	mov [remote_wakeup_status], A

	mov A, BOOT_PROTOCOL
	mov [protocol_status], A

;
; test what kind of reset occurred 
;
	iord Status_Control
	and A, USBReset			; test for USB Bus Reset
	jnz BusReset

	iord Status_Control
	and A, WatchDogReset		; test for Watch Dog Reset
	jz suspendReset
;
; Process a watchdog reset.  Wait for a Bus Reset to bring the system
; alive again.

	mov A, TIMER_ONLY			; enable one msec timer interrupt
	mov [interrupt_mask],A
	iowr Global_Interrupt

WatchdogHandler:				; wait for USB Bus Reset
	jmp WatchdogHandler
suspendReset:
	mov A, 09h
	iowr Status_Control		; go back to suspend
	nop
	jmp suspendReset			; wait until real bus reset
;
; Either a bus reset or a normal reset has occurred
;
BusReset:
	mov A, RunBit			; clear all reset bits
	iowr Status_Control

; setup for enumeration
	mov A, ENUMERATE_MASK	
	mov [interrupt_mask],A
	iowr Global_Interrupt

wait:				; wait until configured
	iord USB_EP1_TX_Config
	cmp A, 0		
	jz wait	

;*******************************************************
; main loop 
;	Purpose: This routine is the code for implementing
;		 a mouse function.  It is divided into three
;		 parts; buttons, horizontal movement, and
;		 vertical movement.  See the documentation
;		 for an explanation of the movement
;		 state machines.
;
;*******************************************************
main:
	iord Port0_Data		; read and store port 0
	mov [port_temp], A
	call ReadButtons		; read the buttons
	call CheckHorizontal	; check for horizontal movement
	call CheckVertical	; check for vertical movement

     
      mov A, [horizontal]	
	cmp A, 0h
	jz NoChangeHorizontal
      jmp send_packet
NoChangeHorizontal:
	mov A, [vertical]	
	cmp A, 0h
	jz NoChangeVertical
      jmp send_packet             
NoChangeVertical:
	mov A, [button_flag]	
	cmp A, 0h
	jz NoChangeButtons
	jnz send_packet
NoChangeButtons:                              
      mov A, [idle_period]                    ;if idle period is 0
      cmp A, 0h                               ;report is sent only if changes 
      jz Nosend

	dec A					; check if idle_period <= idle_period_counter
	cmp A, [idle_period_counter]
      jnc Nosend
      
send_packet:
	iord USB_EP1_TX_Config
	and A, 80h
	cmp A, 80h
	jz Nosend
	mov A, [horizontal]	
	mov [horiz_position], A	
	mov A, [vertical]	
	mov [vert_position], A
	mov A, [buttons]	
	mov [button_position], A	
	iord USB_EP1_TX_Config
	and A, DataToggle		; keep the data 0/1 bit
	or A, 93h			; enable transmit 3 bytes
	iowr USB_EP1_TX_Config

      mov A,[new_idle_flag]  ;if it received a new idle
      cmp A,0                   ;period 4 ms before the previous one
      jz prev_idle              ;counted finishes, need to upgrade
      mov A,[new_idle_period]   ;with a new value
	mov [idle_period],A
      mov A,0
      mov [new_idle_flag],A 
	jmp reset_idle_period_counter 
prev_idle:                     ;
;      mov A,[prev_idle_period]
;      mov [idle_period],A

reset_idle_period_counter: 
      mov A,0
      mov [idle_period_counter],A
	mov [horizontal], A
	mov [vertical], A
	mov [button_flag], A
Nosend:
	jmp main

;========================================================================
; Read the mouse buttons.  If the buttons have changed from the last
; value read, then enable data transmission from endpoint one.
;
; Hardware has buttons in MRL order.  We need to translate them
; to data bits [2:0].
;
;       Port 0 bit[6]   Middle  => bit 2
;       Port 0 bit[5]   Right   => bit 1
;       Port 0 bit[4]   Left    => bit 0
;
ReadButtons:
	mov A, [button1_deb]
	cmp A, 0h
	jnz DoneButtons

	mov A, [port_temp]
	cpl A				; buttons are now 1 when pressed

	asr				; [6:4] => [5:3]
	asr				; [5:3] => [4:2]
	asr				; [4:2] => [3:1]
      asr                     ; [3:1] => [2:0]
      and A, 7h               ; mask out non-buttons
	
	cmp A,[buttons]		; have buttons changed?
	jz DoneButtons

	mov [buttons], A		; move buttons to dma buffer
	mov A, 01h
	mov [button_flag], A
	mov A, 01h
	mov [button1_deb], A

DoneButtons:
	ret				; return to main loop

;========================================================================
; This is a state transition table (16 bytes) that has four input bits:
; 	bit [3:2]	previous state
;	bit [1:0]	current state
;
; The state sequences are:
;	00 => 01 => 11 => 10	increment
;	00 => 10 => 11 => 01	decrement
;
;	00 00 =>  0	00 01 =>  1	00 10 => -1	00 11 =>  0
;	01 00 => -1	01 01 =>  0	01 10 =>  0	01 11 =>  1
;	10 00 =>  1	10 01 =>  0	10 10 =>  0	10 11 => -1
;	11 00 =>  0	11 01 => -1	11 10 =>  1	11 11 =>  0
; 
; The count stays the same if either the states are the same or the
; state changed by two transitions (jump).   
;
	XPAGEOFF		; do not insert XPAGE instructions in a table
StateTable:
	db  0,  1, -1,  0
	db -1,  0,  0,  1
	db  1,  0,  0, -1 
	db  0, -1,  1,  0
	XPAGEON		; insert XPAGE instructions automatically

; If the wheels are configured backwards the StateTable matrix
; 1's and -1's should be exchanged to flip the x and y directions.
; If only one direction has its wheels configured backwards then
; two seperate StateTables should be used and one of them will
; need the 1 to -1 and vice versa exchange.
; A wheel is configured backwards if the two phototransistors 
; associated with it are connected in opposite order to this
; reference design.

;========================================================================
; Check for horizontal movement of the mouse.
;
CheckHorizontal:
	mov A, [port_temp]	; load current state
	and A, 3h			; mask out the rest of the bits
	push A			; save the current state on stack
	or A, [horiz_state]	; include the previous state
	index StateTable		; read increment from PROM	

	add A, [horizontal]	; add increment
	mov [horizontal], A	

	pop A				; restore current state from stack
	asl				; bit[1:0] => bit[2:1]
	asl				; bit[2:1] => bit[3:2]
	mov [horiz_state],A	; update previous state in memory
	ret
;========================================================================
; Check for vertical movement of the mouse.  The first time I tried this,
; the horizontal movement worked and the vertical movement was backward.
; To correct the problem, the current and next states are switched in the
; check vertical routine when compared with the horizontal states.
;
CheckVertical:
	mov A, [port_temp]	; load current state
	and A, 0ch			; mask out the rest of the bits
	push A			; save the current state on stack
	or A, [vert_state]	; include the previous state
	index StateTable		; read increment from PROM	

	add A, [vertical]		; add increment
	mov [vertical], A	

	pop A				; restore current state from stack
      asr A                   ; bit[3:2] => bit[2:1]
      asr A                   ; bit[2:1] => bit[1:0]
      mov [vert_state],A	; update previous state in memory
	ret


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
;========================================================================
; The endpoint zero interrupt service routine supports the control
; endpoint.  This firmware enumerates and configures the hardware.
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
        cmp A, A2h				; *** not in HID spec ***
        jz RequestTypeA2        		; bmRequestType = 10100010 interface

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
; specified interface.  As the mouse only has one interface setting,
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
; interface.  There are no alternate settings for the mouse.
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
; Set Idle				bRequest = 10
      cmp A, set_idle
      jz SetIdle
; Set Protocol			bRequest = 11
      cmp A, set_protocol
      jz SetProtocol
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

;=======================================================================
; This one is not in the spec, but has been captured with CATC while
; Memphis beta testing. 
RequestTypeA2:
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
; Remote wakeup is the ability to wakeup a system from power down mode
; when the user presses a key or moves a mouse.  These routines
; allow the host to enable/disable the ability to request remote wakeup.
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
	jmp SendStall	; *** not supported ***

; Set Idle silences a particular report on the interrupt pipe until a new
; event occurs or the specified amount of time (wValue) passes.
SetIdle:
        
;      mov A, [idle_period]		
;    	 mov [prev_idle_period], A		; set the previous idle period to the current one

	mov A, [wValueHi]				; load upper byte of wValue
	mov [new_idle_period], A		; copy to new_idle_period
	
	mov A, 0					; if current idle_period is 0 (indefinite)
	cmp A, [idle_period]			; set the idle_period to the new_idle_period
	jz set_new_idle_period
	
	mov A, [idle_period]
	sub A, [idle_period_counter]
	jc set_new_idle_flag			; if idle_period < idle_period_counter then 
							; set new idle flag to true

	cmp A, 2					; if the idle_period - idle_period_counter > 1
	jnc set_new_idle_period			; (i.e. > 4ms), then set idle period to new one
							; otherwise, set the new idle flag to true

set_new_idle_flag:				; set the new_idle_flag to 1 and return
	mov A, 1					; this keeps the current idle period until
	mov [new_idle_flag], A			; the next report is sent to the host
	jmp done_SetIdle	


set_new_idle_period:				
	mov A, [new_idle_period]		; set the current idle period to the new one
	mov [idle_period], A

	dec A						; check if new_idle_period <= idle_period_counter
	cmp A, [idle_period_counter]
	jnc done_SetIdle				; if no, then return
	mov A, 1					; if yes, then set new_idle_flag to true so that
	mov [new_idle_flag], A			; we keep the new idle value after the report is sent

done_SetIdle:
	call no_data_control            ; handshake with host
      ret                             ; return

	

        
; Set Protocol switches between the boot protocol and the report protocol.
; For boot protocol, wValue=0.  For report protocol, wValue=1.
; Note, the mouse firmware does not actually do anything with the
; protocol status, yet.
SetProtocol:
        mov A, [wValue]                 ; load wValue
        mov [protocol_status], A        ; write new protocol value
        call no_data_control            ; handshake with host
        ret                             ; return

; Get Report allows the host to receive a report via the control pipe.
; The report type is specified in the wValue high byte while the low
; byte has a report ID.  
GetReport:
        mov A, 3                        ; three byte
        mov [data_count], A
        mov A,report_buffer
        jmp execute2                    ; send report to host
        
	

GetReportDescriptor:
	mov A, (end_hid_report_desc_table - hid_report_desc_table)
      mov [data_count], A             ; save descriptor length            

	mov A, (hid_report_desc_table - control_read_table)
      call execute                    ; send descriptor to host
;
; Enumeration is complete!  
;
      ret                           ; return


; Get Idle reads the current idle rate for a particular input report.
GetIdle:
        
	  mov A, 1                        ; send one byte
        mov [data_count], A
        mov A, new_idle_period
        jmp execute2                     ; send idle_period to host
        

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
execute2:                               ; send the descriptors
        mov [data_start], A             ; save start index
        call get_descriptor_length      ; correct the descriptor length
        call control_read2              ; perform control read function from 
                                        ; the RAM
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
      cmp A, 04h
	jz ConfigurationString
      cmp A, 05h
	jz InterfaceString

; No other strings supported
      jmp SendStall   		; *** not supported ***
LanguageString:
	mov A, (USBStringDescription1 - USBStringLanguageDescription)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringLanguageDescription - control_read_table)
      jmp execute                     ; send the string descriptor
ManufacturerString:	
	mov A, ( USBStringDescription2 - USBStringDescription1)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringDescription1 - control_read_table)
      jmp execute                     ; send the string descriptor
ProductString:
	mov A, ( USBStringDescription3 - USBStringDescription2)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringDescription2 - control_read_table)
      jmp execute                     ; send the string descriptor
SerialNumString:
	mov A, ( USBStringDescription4 - USBStringDescription3)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringDescription3 - control_read_table)
      jmp execute                     ; send the string descriptor
ConfigurationString:
	mov A, ( USBStringDescription5 - USBStringDescription4)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringDescription4 - control_read_table)
      jmp execute
InterfaceString:
	mov A, ( USBStringEnd - USBStringDescription5)
      mov [data_count], A               ; save the descriptor length
	mov A, (USBStringDescription5 - control_read_table)
      jmp execute
	

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
	cmp A, 00h				; if the number of byte to transmit
	jz dma_load_done			; is a multiple of 8 we have to transmit 
						; a zero-byte data packet

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

;========================================================================

;******************************************************
;
;	function:  Control_read2
;	Purpose:   Performs the control read operation. 
;		     Sends data from RAM
;	SETUP-IN-IN-IN...OUT
;
;	data_start: must be set to the beginning of the
;		    RAM buffer
;		    
;	data_count: must be set to the size of the 
;		      buffer 
;******************************************************

control_read2: 
	push X				; save X on stack
	mov A, 00h				; clear data 0/1 bit
	mov [endp0_data_toggle], A

control_read_data_stage2:
	mov X, 00h
	mov A, 00h
	mov [loop_counter], A
	iowr USB_EP0_RX_Status		; clear setup bit

; Fixing a bug seen by NEC hosts	
	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz control_read_status_stage2	; has arrived. Exit ISR
	mov A, 08h				; set BADOUTS BIT
	iowr USB_Status_Control
      mov A, [data_count]
	cmp A, 00h				; if the number of byte to transmit
	jz dma_load_done2			; is a multiple of 8 we have to transmit 
						; a zero-byte data packet

dma_load_loop2:				; loop to load data into the data buffer
	push X
	mov X, [data_start]
	mov A,[X+0]
      pop X
	mov [X + endpoint_0], A		; load dma buffer
	inc [data_start]
	inc X
	inc [loop_counter]
	dec [data_count]			; exit if descriptor
	jz dma_load_done2			; is done
	mov A, [loop_counter]		; or 8 bytes sent
	cmp A, 08h
	jnz dma_load_loop2

dma_load_done2:

	iord USB_EP0_RX_Status		; check setup bit
	and A, 01h				; if not cleared, another setup
	jnz control_read_status_stage2	; has arrived. Exit ISR
	mov A, [endp0_data_toggle]
	xor A, 40h
	mov [endp0_data_toggle], A
	or A, 80h
	or A, [loop_counter]
	iowr USB_EP0_TX_Config
	mov A, [interrupt_mask]
	iowr Global_Interrupt

wait_control_read2:
	iord USB_EP0_TX_Config		; wait for the data to be
	and A, 80h				; transfered
	jz control_read_data_stage2
	iord USB_EP0_RX_Status
	and A, 02h				; check if out was sent by host
	jz wait_control_read2
control_read_status_stage2:		; OUT at end of data transfer
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
	db	12h		; size of descriptor (18 bytes)
	db	01h		; descriptor type (device descriptor)
	db	00h, 01h	; USB spec release (ver 1.0)
	db	00h		; class code (each interface specifies class information)
	db	00h		; device sub-class (must be set to 0 because class code is 0)
	db	00h		; device protocol (no class specific protocol)
	db	08h		; maximum packet size (8 bytes)
	db	B4h, 04h	; vendor ID (note Cypress vendor ID)
	db	01h, 00h	; product ID (Cypress USB mouse product ID)
	db	00h, 00h	; device release number
	db	01h		; index of manufacturer string 
	db	02h		; index of product string 
	db	00h		; index of serial number (0=none)
	db	01h		; number of configurations (1)

   config_desc_table:
	db	09h		; length of descriptor (9 bytes)
	db	02h		; descriptor type (CONFIGURATION)
	db	22h, 00h	; total length of descriptor (34 bytes)
	db	01h		; number of interfaces to configure (1)
	db	01h		; configuration value (1)
	db	04h		; configuration string index 
	db	A0h		; configuration attributes (bus powered)
	db	32h		; maximum power (100mA)

   Interface_Descriptor:
	db	09h		; length of descriptor (9 bytes)
	db	04h		; descriptor type (INTERFACE)
	db	00h		; interface number (0)
	db	00h		; alternate setting (0)
	db	01h		; number of endpoints (1)
	db	03h		; interface class (3..defined by USB spec)
	db	01h		; interface sub-class (1..defined by USB spec)
	db	02h		; interface protocol (2..defined by USB spec)
	db	05h		; interface string index 

   Class_Descriptor:
	db	09h		; descriptor size (9 bytes)
	db	21h		; descriptor type (HID)
	db	00h,01h		; HID class release number (1.00)
	db	00h		; Localized country code (none)
	db	01h		; # of HID class descriptor to follow (1)
	db	22h		; Report descriptor type (HID)
	db	(end_hid_report_desc_table - hid_report_desc_table)
	db	00h

   Endpoint_Descriptor:
	db	07h		; descriptor length (7 bytes)
	db	05h		; descriptor type (ENDPOINT)
	db	81h		; endpoint address (IN endpoint, endpoint 1)
	db	03h		; endpoint attributes (interrupt)
	db	03h, 00h	; maximum packet size (3 bytes)
	db	0Ah		; polling interval (10ms)


   end_config_desc_table:

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
   end_hid_report_desc_table:
;========================================================================

; String Descriptors
; string 0
USBStringLanguageDescription:
    db 04h          ; Length
    db 03h          ; Type (3=string)
    db 09h          ; Language:  English
    db 04h          ; Sub-language: US

; string 1
USBStringDescription1:	; IManufacturerName
    db 18h          ; Length
    db 03h          ; Type (3=string)
    dsu "Cypress Sem." ;

; string 2
USBStringDescription2:	; IProduct
    db 24h          ; Length
    db 03h          ; Type (3=string)
    dsu "Cypress USB Mouse"  ;

;string 3
USBStringDescription3:	; serial number
                        ; If a SN is used, this must be unique
                        ; for every device or the device may
                        ; not enumerate properly
; string 4                 
USBStringDescription4:	; configuration string descriptor
    db 14h          ; Length
    db 03h          ; Type (3=string)
    dsu "HID Mouse"  ;

;string 5
USBStringDescription5:	; configuration string descriptor
    db 32h          ; Length
    db 03h          ; Type (3=string)
    dsu "EndPoint1 Interrupt Pipe"  ;



USBStringEnd:

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