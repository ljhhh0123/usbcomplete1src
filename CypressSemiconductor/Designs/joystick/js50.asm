;***********************************************************************
;				Cypress Semiconductor
; 			Joystick Demonstration Design Kit Firmware 
;
; Features :
; Four Fire Buttons
; Four Hat Buttons
; X, Y, Z movement
; Throttle
; Passes Chapter 9 and Hidview Tests 
; Includes Suspend/Resume Feature
;
; This firmware file is for demonstration purposes only.  
; Cypress Semiconductor will not assume any liability for its use.
; 
;=======================================================================
; 1/20/98	wmh	v5.0 Minor changes in One_msec_ISR
;=======================================================================
; 12/10/97	wmh	v4.9 Minor changes in One_msec_ISR, main and Reset
; Watchdog timer reset in main.
;=======================================================================
; 10/27/97	wmh	v4.8	Change in One_msec_ISR
; Code Naks whenever the joystick is not moved.
; Code also Naks after enumeration for a period approx. 230msec
; This solves blue screen problem when the power is turned off then on
;=======================================================================
; 10/13/97	wmh	v4.6	Change in USB_EP0_ISR
; SetConfiguration request was changed so as to enable endpoint 1
; GetReport is stalled
; GetReportDescriptor sends HID Report Descriptor
;=======================================================================
; 9/8/97	wmh 	v4.5 	Joystick Jitter Solved
; Jitter Solution added to GPIO_ISR 
;=======================================================================
; 8/13/97	wmh 	v4.3 	Report Descriptor Change
; Solves unusual jump in joystick movement
;=======================================================================
; 8/11/97	wmh 	v4.2	ipret change
; changed ret to ipret whenever needed in all subroutines
;=======================================================================
; 8/8/97	wmh	v4.0	One_msec and GPIO ISR changes
; Changes to prevent Endpoint_1 from interrupting capacitor charging
; to prevent jitter effect
;========================================================================
; 8/8/97	wmh 	v3.9	change in Report Descriptor
; Logical and Physical Min and Max have been changed to 3 bytes if > 127
; Other changes were also done
;========================================================================
; 7/3/97	wmh	v3.7 add features
; Suspend/Resume features have been added
; Main work done in the One_mSec_ISR
;========================================================================
; 6/30/97	wmh	v3.6 add features
; changes to allow the code to pass chapter 9 and hidview tests have been
; done.  That meant major rework of the endpoint zero interrupt service
; routine (USB_EP0_ISR).
;=======================================================
; rev 3.5	4/17/97 gwg
; Changed the interrupt mask from a constant to a variable.
; This allows us to enable only the one msec timer and
; EP0 during enumeration.
;
; Tim Williams found a problem with the hat buttons.  I
; forgot the buttons were in the upper nibble.
;=======================================================
; rev 3.4	4/15/97 gwg	664 bytes
; 1. The endpoint one ISR only toggles the Data 0/1 bit
;    now.
; 2. Every four msec, the one msec ISR writes to the
;    USB_EP1_TX_Config register to enable response to IN
;    packets from the host.
; 3. Write measured data directly into the endpoint one 
;    dma buffer.
; 4. Code compatible with revision 2 and 3 silicon.
;=======================================================
; rev 3.3       4/11/97 gwg
; modified for IPRET instruction in an effort to improve
; the runtime.
;=======================================================
; rev 3.2       4/11/97 gwg
; Tim Williams found a bug in the GPIO_ISR that prevented
; the code from working in the chip.  There was not enough
; time allowed to discharge the timing capacitors before
; interrupts were enabled.
;=======================================================
; rev 3.1       4/8/97  gwg
; Replaced Send_Buffer macro with a subroutine.
;=======================================================
; rev 3.0       4/8/97  gwg
; reworked the code to support the hat buttons and up to
; four analog channels.  The analog channels are sampled
; one per msec.  With a channel sample rate of 250 hz, 
; each channel should have a bandwidth of 125 hz - good.
; 
; The buttons are sampled in the main loop at a much
; higher rate.  
;
; The Send_Buffer macro remains a code size problem as
; the result to date is 40 bytes over 2 kilobytes.
;=======================================================
; rev 2.1       3/29/97 gwg
; reworked the code to eliminate string indices in the
; descriptors.  We don't have any strings.  Also fixed
; an error in the HID length (114 => 116 bytes)
;=======================================================
; drastic rework of js63fa.asm on 3/25 by gwg
;*******************************************************
;  This version of code supports the joystick function
;  and four buttons.
;*******************************************************
; 1. Eliminated the "scaling" feature that tried to 
;    ensure the joystick returned full-range readings.
; 2. Converted the analog measurement sections into two
;    subroutines.
; 3. Fixed several interrupt enable and stack problems
;    with the USB interrupt service routines.
; 4. Initialized the part to work correctly in a joystick:
;       - program pullup registers
;       - program Isink registers
; 5. Enabled the one msec interrupt handler to clear the
;    watchdog.
; 6. Patched the USB EP0 ISR to set the BadOuts bit to
;    accomodate changes in the chip definition.
; 7. Rewrote the USB interrupt handlers for better flow
;    and to remove redundant load instructions.
; 8. Commented the code to describe how it works. 
;*******************************************************
;               Suggested Changes
;-------------------------------------------------------
; 1. Convert the Send_Buffer macro to a subroutine to
;    reduce the code size.  The current version is 2 KB
;    plus 22 bytes.
; 2. Add hat support as either:
;       - third analog channel (software only)
;       - four buttons (rework hardware)
; 3. Add throttle support as another analog channel.
;    Consolidate the measure subroutines into one routine
;    that can process a selectable channel.
;*******************************************************
;               Suggestions for the Assembler
;-------------------------------------------------------
; 1. The assembler should be able to assign variable
;    addresses automatically.  One method is the concept
;    of segments: "data" and "code".  An ORG directive
;    would include a parameter to indicate which type of
;    segment was intended.  Then DB, DW, etc. would
;    allocate variable space and automatically assign 
;    the addresses.
; 2. We need a linker that allows us to write modular
;    code and link modules together.   
; 3. Conditional assembly directives would be useful to
;    write common code to support multiple parts.
;*******************************************************

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
Status_Control:         equ     FFh

; constants - gwg
BUTTON_MASK:            equ     0Fh     ; button bits
HAT_MASK:               equ     F0h     ; hat bits
FORWARD:                equ     1       ; hat forward
RIGHT:                  equ     3       ; hat right
BACK:                   equ     5       ; hat back
LEFT:                   equ     7       ; hat left
;**********  Register constants  ************************************
; Processor Status and Control
RunBit:			equ	 1h	; CPU Run bit
USBReset:			equ	20h	; USB Bus Reset bit
WatchDogReset:		equ	40h	; Watchdog Reset bit

; interrupt masks
TIMER_ONLY:			equ	 4h	; one msec timer

ENUMERATE_MASK:		equ	0Ch	; one msec timer 	
						; USB EP0 interrupt

RUNTIME_MASK:		equ     5Ch     	; one msec timer
							; USB EP0 interrupt
							; USB EP1 interrupt
							; GPIO interrupt
; USB EP1 transmit configuration
DataToggle:			equ	40h	; Data 0/1 bit

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
 

; data memory variables
;------------------------------------------------------------------------
; To support the USB specification.
remote_wakeup_status:   equ  30h       	; remote wakeup request
							; zero is disabled
							; two is enabled
configuration_status:   equ  31h        	; configuration status
							; zero is unconfigured
							; one is configured
;idle_status:           equ  33h        	; support SetIdle and GetIdle
protocol_status:      	equ  34h        	; zero is boot protocol
							; one is report protocol
suspend_counter:		equ 35h		; contains number of idle bus msecs 
jitter_temp:		equ 36h	
loop_temp:			equ 37h
start_send:			equ 38h
X_Value_old:                equ  39h        
Y_Value_old:                equ  40h        
Z_Value_old:                equ  41h        
hat_bits_old:               equ  42h        
button_bits_old:            equ  43h        
Throttle_old:               equ  44h        

	
;------------------------------------------------------------------------

; variable allocations
temp:                   equ  25h
start_time:             equ  21h
testbit:                equ  22h
interrupt_mask:		equ  20h
endp0_data_toggle: 	equ  23h
loop_counter:		equ  24h
data_start:			equ  27h
data_count:			equ  28h
endpoint_stall:		equ  29h

; interrupt endpoint 1 fifo
endpoint_1:             equ  78h
X_Value:                equ  78h        ; Port 1 bit 0
Y_Value:                equ  79h        ; Port 1 bit 1
Z_Value:                equ  7Ah        ; Port 1 bit 3
hat_bits:               equ  7Bh        ; Port 0 bits 7:4
button_bits:            equ  7Ch        ; Port 0 bits 3:0
Throttle:               equ  7Dh        ; Port 1 bit 2

;*************** interrupt vector table ****************
; begin execution here after a reset
org  00h                ; Reset vector
jmp  Reset

org  02h                ; 128us interrupt
jmp  DoNothing_ISR

org  04h                ; 1024ms interrupt 
jmp  One_mSec_ISR

org  06h                ; endpoint 0 interrupt 
jmp  USB_EP0_ISR

org  08h                ; endpoint 1 interrupt 
jmp  USB_EP1_ISR

org  0Ah                ; reserved interrupt 
jmp  Reset

org  0Ch                ; general purpose I/O interrupt 
jmp  GPIO_ISR           ; not used

org  0Eh                ; Wakeup_ISR or resume interrupt 
jmp  DoNothing_ISR      ; not used


ORG  10h
;************************************************************************
; The 128 uSec, Cext, is not used by the joystick code.
; If this interrupt occurs, the software should do nothing
; except re-enable the interrupts.
DoNothing_ISR:
	push A                  ; save accumulator on stack
	mov A,[interrupt_mask]
      ipret Global_Interrupt  ; enable interrupts and return

;************************************************************************
; The 1 msec interrupt is used to check for suspend and start an
; analog measurement.     
One_mSec_ISR:
	push A                  	; save accumulator on stack
	mov A, [loop_temp]		; Before enumeration end value is zero
	cmp A, 0h
	jz not_main				; Enumeration has not ended 
	dec [loop_temp]			; Enumeration ended decrement counter
not_main:					
; suspend checking
	iord USB_Status_Control		; check if there is no bus activity
	and A, 01h
	cmp A,0h
	jz Inc_counter			; no bus activity
	iord USB_Status_Control		; clear the bus activity bit
	and A, 0FEh
	iowr USB_Status_Control
	mov A, 0h				; clear the suspend counter
	mov [suspend_counter], A
	jmp Suspend_end
Inc_counter:
	inc [suspend_counter]
	mov A, [suspend_counter]	; get idle msec counts
	cmp A, 03h				; check if 3msecs of bus inactivity passed
	jnz Suspend_end			; less than 3msecs
	mov A, 0h				; clear the suspend counter
	mov [suspend_counter], A
	mov A, 0h			; Enable Pullup on port1 lines
	iowr Port1_Pullup
	mov A, 0ffh
	iowr Port1_Data
	iord Status_Control		;set the suspend bit causing suspend
	or A, 08h
	iowr Status_Control	
	nop	
	mov A, 0ffh			; Disable Pullup on port1 lines
	iowr Port1_Pullup
	mov A, 0h
	iowr Port1_Data
	
Suspend_end:
; Starting an analog measurement requires three steps:  
;       1. discharge the timing capacitor
;       2. start charging the timing capacitor
;       3. read and save the start time.
	and A, 0h			; clear carry flag
	mov A, [testbit]        	; select analog channel for measurement
	rrc A
	jnz storeBit

	iord USB_EP1_TX_Config
	cmp A,0                 	; test whether endpoint enabled
	jz Select
	mov A, [start_send]
	cmp A, 01h
	jnz Select
; Check if values have changed
 	mov A, [X_Value_old]
	cmp A, [X_Value]
	jnz send_value
 	mov A, [Y_Value_old]
	cmp A, [Y_Value]
	jnz send_value
 	mov A, [Z_Value_old]
	cmp A, [Z_Value]
	jnz send_value
	mov A, [hat_bits_old]
	cmp A, [hat_bits]
	jnz send_value
	mov A, [button_bits_old]
	cmp A, [button_bits]
	jnz send_value
	mov A, [Throttle_old]
	cmp A, [Throttle]
	jnz send_value
	jmp Select
send_value:
	iord USB_EP1_TX_Config
	and A,40h               	; keep the Data 0/1 bit
	or A,96h                	; enable transmit 6 bytes
	iowr USB_EP1_TX_Config

; Save transmitted values as old values
 	mov A, [X_Value]
	mov [X_Value_old], A
 	mov A, [Y_Value]
	mov [Y_Value_old], A
 	mov A, [Z_Value]
	mov [Z_Value_old], A
	mov A, [hat_bits]
	mov [hat_bits_old], A
	mov A, [button_bits]
	mov [button_bits_old], A
	mov A, [Throttle]
	mov [Throttle_old], A

Select:
	mov A,8				; select fourth channel

storeBit:
	mov [testbit],A         	; start charge cycle
	iowr Port1_Data

; The initial assumption is the start time will always be zero, since
; the measurement is synced with the one millisecond interrupt.  The
; problem with that assumption is there could be a delay due to a USB
; ISR before this interrupt is recognized.

	iord Timer              	; read free-running timer
	mov [start_time],A      	; save start value

	mov A,[interrupt_mask]		; prevent endpoint_1 interrupts
	and A, EFh				; preventing jitter
	mov [interrupt_mask],A	

       ipret Global_Interrupt  	; enable interrupts and return

;************************************************************************
; The GPIO interrupt will be the end of an analog measurement on one
; of the four analog input channels in Port 1.  Complete the measurement
; as a time critical problem, then setup for the next measurement.

GPIO_ISR:
	push A                  ; save the accumulator to stack
	push X                  ; save X on stack
	iord Timer              ; read timer
	push A                  ; save stop time value
	mov A,0                 ; discharge timing capacitor
	iowr Port1_Data

; We need to convert from a bit map to an index that allows us to store
; the result:
;       0001    => 000 X 
;       0010    => 001 Y
;       0100    => 101 Throttle
;       1000    => 010 Z

	mov X,0                 ; clear counter
	mov A,[testbit]         ; load bit under test

	rrc A                   ; test X value
	jc done                 ; index=0 for X value

	inc X
	rrc A                   ; test Y value
	jc done                 ; index=1 for Y value

	mov X,5
	rrc A                   ; test Throttle         
	jc done                 ; index=5 for Throttle

	mov X,2                 ; index=2 for Z value
;****************************************************************
;			Jitter minimization subroutine
; In this subroutine the value of the joystick movement is being
; calculated and the jitter is being minimized by reducing the 
; precision by 2 bits.
done:
	pop A                   ; restore stop time value
	sub A,[start_time]      ; calculate the difference
	mov [jitter_temp],A
	mov A, [X+endpoint_1]	; get previous value
	cmp A, [jitter_temp]	; compare previous to current value
	jc next_minus_prev
	sub A, [jitter_temp]	; previous > current
	jmp check_diff
next_minus_prev:
	mov A, [jitter_temp]	; current > previous
	sub A, [X+endpoint_1]
check_diff:
	cmp A, 4h			; check difference 
	jnc nojitter
	mov A, [X+endpoint_1]	; send previous value
	mov [jitter_temp],A
nojitter:
	mov A, [jitter_temp]	; send current value
	mov [X+endpoint_1],A    ; store the measurement
	pop X                   ; restore X from stack

	mov A, [interrupt_mask] ; enable enpoint_1 interrupts
	or A, 10h			
	mov [interrupt_mask],A	

      ipret Global_Interrupt  ; enable interrupts and return

;********************** Endpoint_1_ISR **************************

USB_EP1_ISR:
	push A          		; save accumulator on stack

	iord USB_EP1_TX_Config  
	xor A,40h               ; flip data 0/1 bit
	iowr USB_EP1_TX_Config

	mov A, [interrupt_mask]
      ipret Global_Interrupt  ; enable interrupts and return

;************************************************************************
; reset processing
; The idea is to put the microcontroller in a known state.  As this
; is the entry point for the "reserved" interrupt vector, we may not
; assume the processor has actually been reset and must write to all
; of the I/O ports. 
Reset:
	mov A, endpoint_0               ; move data stack pointer
	swap A, dsp                     ; so it does not write over USB FIFOs 

	mov A, 0ffh                     ; load accumulator with ones

	iowr Port0_Data                 ; output ones to port 0
	iowr Port1_Pullup               ; disable port 1 pullups
						  ; select rising edge interrupts
	iowr Port1_Isink0               ; maximum isink current Port1 bit 0
	iowr Port1_Isink1               ; maximum isink current Port1 bit 1
	iowr Port1_Isink2               ; maximum isink current Port1 bit 2
	iowr Port1_Isink3               ; maximum isink current Port1 bit 3

	mov A, 0h                       ; load accumulator with zeros

	iowr Port1_Data                 ; output zeros to port 1
	iowr Port0_Interrupt            ; disable port 0 interrupts
	iowr Port0_Pullup               ; enable port 0 pullups
	iowr Port0_Isink0               ; minimum sink current Port0 bit 0
	iowr Port0_Isink1               ; minimum sink current Port0 bit 1
	iowr Port0_Isink2               ; minimum sink current Port0 bit 2
	iowr Port0_Isink3               ; minimum sink current Port0 bit 3
	iowr Port0_Isink4               ; minimum sink current Port0 bit 4
	iowr Port0_Isink5               ; minimum sink current Port0 bit 5
	iowr Port0_Isink6               ; minimum sink current Port0 bit 6
	iowr Port0_Isink7               ; minimum sink current Port0 bit 7

	mov [hat_bits],A                ; clear remembered hat bits

	mov A, 80h                      ; default the analog channels
	mov [X_Value],A                 ; X axis
	mov [Y_Value],A                 ; Y axis
	mov [Z_Value],A                 ; Z axis (rotation)
	mov [Throttle],A                ; throttle

	mov A,8                         ; initialize analog channel
	mov [testbit],A                 ; select channel four

	mov A, 0h
	mov [endpoint_stall], A
	mov [remote_wakeup_status], A
	mov [configuration_status], A
	mov [loop_temp], A
	mov [start_send], A
	mov [X_Value_old], A
	mov [Y_Value_old], A
	mov [Z_Value_old], A
	mov [hat_bits_old], A
	mov [button_bits_old], A
	mov [Throttle_old], A

	iowr Watchdog                   ; clear watchdog timer

	mov A, 0fh
	iowr Port1_Interrupt            ; enable port 1 interrupts
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
; A bus reset has occurred
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
	iowr Watchdog           	; clear watchdog timer		
	jz wait	

	mov A, 0ffh				; initializes loop temp
	mov [loop_temp], A
; loop_temp is used to add a delay in the start of transmission of data
; The delay will start after reaching this point.  This means that the 
; transmission of data from endpoint 1 will not start right after enumeration
; is complete but is going to be delayed.  Until the transmission begins 

; the controller will Nak any IN packets to endpoint 1.  If data exists 

; the first IN packet to enpoint 1 that will be responded to with data 
; from the controller is after 230msec from enumeration end.
; This was done to solve driver problems when the joystick was plugged in and
; then the power was recycled or when the joystick was plugged in before the host 
; was turned on.  The joystick driver could not handle the data right after
; enumeration.
;************************************************************************
; This is the main loop that endlessly repeats the same sequence over
; and over.

main:
	mov A, [loop_temp]
	cmp A, 0Ah
	jnc no_set				; do not enable TX yet
	mov A, 01h				; enable transmission
	mov [start_send], A		; after this loop_temp value doesn't matter
no_set:	
	iowr Watchdog           	; clear watchdog timer
	iord Port0_Data                 ; read Port 0
	cpl A                           ; invert the buttons

	push A                          ; save A on stack
	and A,BUTTON_MASK               ; mask button bits
	mov [button_bits], A            ; save the button status
	pop A					  ; restore A from stack

	and A,HAT_MASK
	jz storeHat                     ; no hat button pressed
	mov [temp],A

Test1st:
	and A,10h                       ; test first button
	jz Test2nd                      
	mov A,[temp]
	and A,0E0h                      ; test for multiple buttons
	jnz nochange                    ; hold current state
	mov A,FORWARD                   ; "forward" button is pressed
	jmp storeHat

Test2nd:
	mov A,[temp]
	and A,20h                       ; test second button
	jz Test3rd
	mov A,[temp]
	and A,0D0h                      ; test for multiple buttons
	jnz nochange                    ; hold current state
	mov A,RIGHT                     ; "right" button is pressed
	jmp storeHat

Test3rd:
	mov A,[temp]
	and A,40h                       ; test third button
	jz Test4th
	mov A,[temp]
	and A,0B0h                      ; test for multiple buttons
	jnz nochange                    ; hold current state
	mov A,BACK                      ; "back" button is pressed
	jmp storeHat

Test4th:
	mov A,[temp]
	and A,80h                       ; test fourth button
	jz storeHat                     ; should never happen
	mov A,[temp]
	and A,070h                      ; test for multiple buttons
	jnz nochange                    ; hold current state
	mov A,LEFT                      ; "left" button is pressed

storeHat:
	mov [hat_bits], A               ; save the hat status

nochange:
	jmp main                	  ; loop continuously


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
; specified interface.  As the joystick only has one interface setting,
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
; interface.  There are no alternate settings for the joystick.
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
; Remote wakeup is the ability to wakeup a system from power down mode
; when the user presses a key or moves a joystick.  These routines
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
	mov A, [interrupt_mask]		; enable endpoint one and GPIO interrupts
	or A, 50h
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
; No strings in the joystick code, yet.
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
        jmp SendStall   ; *** not supported ***

; Set Protocol switches between the boot protocol and the report protocol.
; For boot protocol, wValue=0.  For report protocol, wValue=1.
; Note, the joystick firmware does not actually do anything with the
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

	jmp SendStall			  ; currently not supported

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

;**********  ROM lookup tables  *************************************

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
	db B4h,04h      ; Vendor ID (Cypress)
	db 1fh,0fh      ; Product ID (Sidewinder = 0x0f1f)
	db 88h,02h      ; Device release number (2.88)
	db 00h          ; Mfr string descriptor index (None)
	db 00h          ; Product string descriptor index (None)
	db 00h          ; Serial Number string descriptor index (None)
	db 01h          ; Number of possible configurations (1)
end_device_desc_table:

config_desc_table:
	db 09h          ; Descriptor length (9 bytes)
	db 02h          ; Descriptor type (Configuration)
	db 22h,00h      ; Total data length (34 bytes)
	db 01h          ; Interface supported (1)
	db 01h          ; Configuration value (1)
	db 00h          ; Index of string descriptor (None)
	db 80h          ; Configuration (Bus powered)
	db 32h          ; Maximum power consumption (100mA)

Interface_Descriptor:
	db 09h          ; Descriptor length (9 bytes)
	db 04h          ; Descriptor type (Interface)
	db 00h          ; Number of interface (0) 
	db 00h          ; Alternate setting (0)
	db 01h          ; Number of interface endpoint (1)
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
	db (end_hid_report_desc_table - hid_report_desc_table),00h

Endpoint_Descriptor:
	db 07h          ; Descriptor length (7 bytes)
	db 05h          ; Descriptor type (Endpoint)
	db 81h          ; Encoded address (Respond to IN, 1 endpoint)
	db 03h          ; Endpoint attribute (Interrupt transfer)
	db 06h,00h      ; Maximum packet size (6 bytes)
	db 0Ah          ; Polling interval (10 ms)
      
end_config_desc_table:

hid_report_desc_table:   
	db 05h, 01h     ; Usage Page (Generic Desktop)
	db 09h, 04h     ; Usage (Joystick)
	db A1h, 01h     ; Collection (Application)
	db 09h, 01h     ;       Usage (Pointer)
	db A1h, 00h     ;       Collection (Physical)

	db 05h, 01h     ;               Usage Page (Generic Desktop) 
	db 09h, 30h     ;               Usage (X)
	db 09h, 31h     ;               Usage (Y)
	db 15h, 80h     ;               Logical Minimum (-127)
	db 25h, 7Fh     ;               Logical Maximum (127)
	db 35h, 00h     ;               Physical Minimum (0)
	db 45h, FFh	    ;               Physical Maximum (255)
	db 66h, 00h, 00h;               Unit (None (2 bytes))
	db 75h, 08h     ;               Report Size (8)  (bits)
	db 95h, 02h     ;               Report Count (2)  (fields)
	db 81h, 02h     ;               Input (Data, Variable, Absolute)  

	db 09h, 35h     ;               Usage (Rotation about z-axis) 
	db 15h, C0h     ;               Logical Minimum (-64)
	db 25h, 3Fh     ;               Logical Maximum (63)
	db 35h, 00h     ;               Physical Minimum (0)
	db 46h, FFh, 00h;               Physical Maximum (255)
	db 66h, 00h, 00h;               Unit (None (2 bytes))
	db 75h, 08h     ;               Report size (8)
	db 95h, 01h     ;               Report Count (1)
	db 81h, 02h     ;               Input (Data, Variable, Absolute)

	db 09h, 39h     ;               Usage (Hat switch)
	db 15h, 01h     ;               Logical Minimum (1)
	db 25h, 08h     ;               Logical Maximum (8)
	db 36h, 00h, 00h;               Physical Minimum (0) (2 bytes)
	db 46h, 3Bh, 01h;               Physical Maximum (315) (2 bytes)
	db 65h, 14h	    ;               Unit (Degrees)
	db 75h, 08h     ;               Report Size (8)
	db 95h, 01h     ;               Report Count (1)
	db 81h, 02h     ;               Input (Data, Variable, Absolute)

	db 05h, 09h     ;               Usage page (buttons)
	db 19h, 01h     ;               Usage minimum (1)
	db 29h, 04h     ;               Usage maximum (4)
	db 15h, 00h     ;               Logical Minimum (0)
	db 25h, 01h     ;               Logical Maximum (1)
	db 35h, 00h     ;       	  Physical Minimum (0)
	db 45h, 01h	    ;			  Physical Maximum (1)
	db 75h, 01h     ;               Report Size (1)
	db 95h, 04h     ;               Report Count (4)
	db 81h, 02h     ;               Input (Data, Variable, Absolute)

	db 95h, 01h     ;               Report Size (1)
	db 75h, 04h     ;               Report Count (4)
	db 81h, 01h     ;               input (4 bit padding)
	db C0h          ;       End Collection


	db 05h, 01h     ;       Usage Page (Generic Desktop)
	db 09h, 36h     ;       Usage (Slider)
	db 15h, 00h     ;       Logical Minimum (0)
	db 26h, FFh, 00h;       Logical Maximum (255)
	db 35h, 00h     ;       Physical Minimum (0)
	db 46h, FFh, 00h;       Physical Maximum (255)
	db 75h, 08h     ;       Report Size (8)
	db 66h, 00h, 00h;       Unit (None)
	db 95h, 01h     ;       Report Count (1)
	db 81h, 02h     ;       Input (Data, Variable, Absolute)

	db C0h          ; End Collection
end_hid_report_desc_table:

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
