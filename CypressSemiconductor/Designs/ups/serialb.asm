;======================================================================
;		copyright 1997 Cypress Corporation
;======================================================================
; Designer:		J. Brown
; Date:		9/27/97
;======================================================================
; Part Number:	CY7C63000
; File:		Serial3.asm
; Rev:		1.0
;======================================================================
; Comments:
;
;	This code will send generic commands to
;	the RS-232 port of a serial device and reads back
;	the response character string.
;
;	This version of code provides a UART function
;	with the following characteristics:
;
;	1. 2400 baud
;	2. 1 start bit
;	3. 8 data bits
;	4. No parity bit
;	5. 1 stop bit
;
;	5. No framing error support.
;	6. No NACK support.
;	7. No retry support.
;
;======================================================================
; History:
;
; 12/30/97 :
; Clean-up of code for incoportaion to reference designs.
;
;	9/27/97 :
;	Initial code for generic Serial Interface.
;
;======================================================================
; Background:
;
;	The micro-controller transmits 4 character command codes.
;	Upon receipt of a command code, the target device responds with
;	a character string containing the requested information.
;	This character string is terminated with a carriage return/
;	line feed pair. The micro-controller then stores the character
;	string in a local RAM buffer while stripping the line feed
;	character. The carriage return character is retained as the
;	buffer's delimiter.
;
;	If the device receives an unrecognized command it will respond
;	with a NACK character (15h), indicating that the command is
;	unsupported on this model of the product.
;
;	If the miro-controller receives an invalid start bit, it will
;	return to the main routine and await a new start bit.
;
;	If the miro-controller does not detect that the current
;	character is a line feed character, it will retun to the main
;	routine and await the next character.
;
;	No time out retry features are implemented in this version of
;	code.
;
;	Note that all delay loops and time between receive and transmit
;	are dependent on the response timing of the RS-232 peripheral.
;	These relanionships must be adjusted in each design to provide
;	stable communications. This behaviour is due to the lack of
;	hardware handshaking with the peripheral.
;
;	Limited software handshaking is provided by detection of the
;	carriage_return/line_feed pair string terminator.
;
;**********************************************************************
;************************ assembler directives ************************ 
;
;label:          XPAGEON
;
; I/O ports
Port0_Data:		    equ 00h ; GPIO data port 0
Port1_Data:		    equ 01h ; GPIO data port 1
Port0_Interrupt:	equ 04h ; Interrupt enable for port 0
Port1_Interrupt:	equ 05h ; Interrupt enable for port 1
Port0_Pullup:	    equ 08h ; Pullup resistor control for port 0
Port1_Pullup:	    equ 09h ; Pullup resistor control for port 1
;
; GPIO current sink register
Port0_Isink0:	    equ 30h ; 
;
; Variable memory allocations
innerDelayOneCount: equ 3Ah ; Delay One: Inner delay count 
outerDelayOneCount: equ 3Bh ; Delay One: Outer delay count 
innerDelayCount:	  equ 3Ch ; Delay: Inner delay count 
outerDelayCount:	  equ 3Dh ; Delay: Outer delay count 
rxEnable:		        equ 40h ; Receiver Enabled Flag
rxBitCount:		      equ 42h ; Recieve Bits Count
rxFrameCount:	      equ 44h ; Recieve Frame Count
rxData:		          equ 46h ; Receive Data Holding Register
rxBufPtr:		        equ 48h ; Receive Buffer Pointer
rxFrameFlag:	      equ 4Ah ; Framing Error Flag (0=No,1=Yes)
rxPassCount:	      equ 4Bh ; Transmit Buffer Pointer
rxBuf:		          equ 50h ; Recieve Buffer Start
rxBufEnd:		        equ 5Fh ; Recieve Buffer End
txEnable:		        equ 41h ; Transmiter Enabled Flag
txBitCount:		      equ 43h ; Transmit Bits Count
txFrameCount:	      equ 45h ; Transmit Frame Count
txData:		          equ 47h ; Transmit Data Holding Register
txBufPtr:		        equ 49h ; Transmit Buffer Pointer
txBuf:		          equ 4Ch ; Transmit Buffer Start (4 Bytes)
;
; Constant declarations
; Transmit counter values
txStart:	  equ 00h ; Start bit begin
txBit0:	    equ 03h ; Start bit end
txBit1:	    equ 07h ; Data bit 0 end
txBit2:	    equ 0Ah ; Data bit 1 end
txBit3:	    equ 0Dh ; Data bit 2 end
txBit4:	    equ 10h ; Data bit 3 end
txBit5:	    equ 14h ; Data bit 4 end
txBit6:	    equ 17h ; Data bit 5 end
txBit7:	    equ 1Ah ; Data bit 6 end
txStop:	    equ 1Dh ; Data bit 7 end
txComp:	    equ 20h ; Stop bit end
;
txDataMask: equ FEh ; Mask to preserve inputs.
;
; Receive counter values
rxStart:    equ 01h ; Start bit center
rxBit0:	    equ 05h ; Data bit 0 center
rxBit1:	    equ 09h ; Data bit 1 center
rxBit2:	    equ 0Ch ; Data bit 2 center
rxBit3:	    equ 0Fh ; Data bit 3 center
rxBit4:	    equ 12h ; Data bit 4 center
rxBit5:	    equ 16h ; Data bit 5 center
rxBit6:	    equ 19h ; Data bit 6 center
rxBit7:	    equ 1Ch ; Data bit 7 center
rxStop:	    equ 1Fh ; Data bit 7 center
rxComp:	    equ 22h ; Stop bit center
lastrxBit:  equ 07h ; Last receive data bit count
;
; Interrupt masks
GPIO_intMask:	  equ 40h ; Mask for Port 0 GPIO interrupts.
128us_intMask:	equ 02h ; Mask to enable 128us only.
;
; ASCII Characters for commands
;Car_Ret:	  equ 0Dh ; Carriage Return Terminator
;Ln_Fd:	    equ 0Ah ; Line Feed Terminator
;Asc_Space:	equ 20h ; ASCII Space Character
;
;************************************************************************
; If we are recieving a byte of data from the serial channel we need to
; go to the receive subroutine.
Serial_ISR:
	push	A                     ;
	push X                      ;
	mov	A, [rxEnable]           ; Load the receive enable flag.
	cmp	A, 0 			              ; Check for receive in progress.
	jnz	Increment_rxFrameCount  ; Yes, go receive.
;************************************************************************
; If we are sending a byte of data to the serial channel we need to
; go to the transmit subroutine.
;
	mov	A, [txEnable]           ; Check for transmit in progress.
	cmp	A, 0                    ;
	jnz	Increment_txFrameCount  ; Yes, go transmit.
	jmp	done_Serial             ; Default
;
; We are transmitting.
Increment_txFrameCount:
	inc	[txFrameCount]          ; Adjust frame count.
	mov	A, [txFrameCount]       ; Put it in the accumulator
	mov	[txBitCount], A         ; Save it as the new bit count
	jmp	done_Serial             ; Finished
;
; We are receiving.
Increment_rxFrameCount:
	inc	[rxFrameCount]          ; Adjust frame count.
	call	rxRoutine             ; Go get a character
	pop X                       ;
	mov	A, 00h                  ; Disable interrupts and return.
	ipret	Global_Interrupt      ;
;
; Finish the interrupt handling
done_Serial:
	pop X
	mov	A, 128us_intMask        ; Load 128us ISR Enable value
	ipret	Global_Interrupt      ; Return and enable 128us ISR
;
;************************************************************************
; The GPIO interrupt will occur at the start of a receive data byte.
; The low going start bit will trigger the GPIO_ISR.
;
GPIO_ISR:
	push	A	; save the accumulator to stack
	push	X	; save X on stack

; Three steps for detecting the start bit:
; 1.) Check that the receiver generated the interrupt.
;	iord	[Port0_Data]	;
;	and	A, 80h          ;
;	jz	GPIO_ISR_Done   ;
;	jnz	GPIO_ISR_Done	  ;
;
; 2.) Set the receive enable bit.
	mov	A, 01h		          ; Load the accumulator.
	mov	[rxEnable], A	      ; write to the receive enable flag.
;
; 3.) Clear the receive data register.
	mov	A, 00h		          ; Clear the accumulator.
	mov	[rxData], A		      ; Clear the receive data register.
;
GPIO_ISR_Done:
	pop	x			              ; Restore the index register.
	mov	A, 128us_intMask	  ; Load the 128us interrupt mask.
	ipret	Global_Interrupt	; Return to caller.
					                ; 128us interrupt enabled.
;
;************************************************************************
; During serial transfers data bit 0 is transmitted first.
; We will use Port 0 Bit 7 for receive and Bit 0 for transmit.
; Data will always be right shifted for either transmit or receive.
; Port 0 Bit 7 will be a falling edge sensitive GPIO_ISR input.
; Port 0 bits 6-0 and Port 1 bits 3-0 will be outputs.
;
SerialInitialize:
	push	A			        ; Save the accumulator.
	push	X			        ; Save the index.
	mov	A, FFh		      ; load accumulator with ones
	iowr	Port0_Data		; output ones to port 0
	iowr	Port1_Data		; output ones to port 1
;
	mov	A, 00h		; load accumulator with zeros
	iowr	Port0_Pullup	; enable port 0 pullups
	iowr	Port1_Pullup	; enable port 1 pullups
;
	iowr	Port0_Interrupt	; disable port 0 interrupts
	iowr	Port1_Interrupt	; disable port 1 interrupts
;
	mov	A, 08h		      ; load accumulator with med sink
	iowr	Port0_Isink0	; minimum sink current Port0 bit 0
;
;	iowr	Watchdog		  ; clear watchdog timer
;
; Clear the serial channel counters.
	mov	A, 00h
	mov	[rxEnable], A	    ; Clear rxEnable Flag
	mov	[rxBitCount], A	  ; Clear rx bit count.
	mov	[rxFrameCount], A	; Clear rx frame counter.
	mov	[rxBufPtr], A	    ; Clear rx buffer Pointer.
	mov	[txEnable], A	    ; Clear txEnable Flag.
	mov	[txBitCount], A	  ; Clear tx bit count.
	mov	[txFrameCount], A	; Clear tx frame counter.
	mov	[txBufPtr], A	    ; Clear tx buffer Pointer.
;
	mov	A, 81h		        ; Enable port0 bit7 as input.
	iowr	Port0_Data		  ; All other bits are outputs.
	mov	A, 7Eh		        ; Select falling edge interrupt
	iowr	Port0_Pullup	  ; on port0 bit7.
	mov	A, 00h		        ;
	iowr	Port0_Interrupt	; Disable port 0 bit 7 interrupt.
;
	mov	[txBufPtr], A	      ; Reset tx buffer pointer.
	mov	[interrupt_mask], A ; Default all interrupts to disabled.
	pop	X			              ; Restore the index.
	pop	A			              ; Restore the accumulator.
	ret				              ; Return to caller.
;************************************************************************
; TX_Data processing:
; This routine will write a byte of data.
; 1.) Send the active low Start bit.
; 2.) Send eight variable data bits.
; 3.) Send the active high Start bit.
; 4.) Stay in transmit until complete.
;************************************************************************
;
txRoutine:
;  Prepare for the transmit.
	push	A			          ; save accumulator.
	mov	A, 01h		        ; Load txEnable Flag.
	mov	[txEnable], A	    ; Store txEnable Flag.
	mov	A, [txFrameCount]	; Get frame count.
	mov	[txBitCount], A	  ; Save bit count.
;
sendStart:
;  Write out the start bit. (active low)
	mov	A, FEh		          ; Load tx Start bit.
	iowr	Port0_Data		    ; Send tx Start bit.
	mov	A, 02h		          ; Load 128us ISR Enable value.
	iowr	Global_Interrupt	; Enable 128us ISR.
;
;  Check the bit count and send a bit if required.
check_tx_bit:
	mov	A, [txBitCount]	; Get frame count
	cmp	A, txBit0		; tx bit 0 at frame count=03h
	jz	sendtxBit		; Go send data bit
	cmp	A, txBit1		; tx bit 1 at frame count=07h
	jz	sendtxBit		; Go send data bit
	cmp	A, txBit2		; tx bit 2 at frame count=0Ah
	jz	sendtxBit		; Go send data bit
	cmp	A, txBit3		; tx bit 3 at frame count=0Dh
	jz	sendtxBit		; Go send data bit
	cmp	A, txBit4		; tx bit 4 at frame count=10h
	jz	sendtxBit		; Go send data bit
	cmp	A, txBit5		; tx bit 5 at frame count=14h
	jz	sendtxBit		; Go send data bit.
	cmp	A, txBit6		; tx bit 6 at frame count=17h.
	jz	sendtxBit		; Go send data bit.
	cmp	A, txBit7		; tx bit 7 at frame count=1Ah.
	jz	sendtxBit		; Go send data bit.
	cmp	A, txStop		; tx Stop at frame count=1Dh.
	jz	sendStop		; Go send stop bit.
	cmp	A, txComp		; tx Stop at frame count=20h.
	jz	txEnd			  ; Go send end transmit.
	jmp	check_tx_bit	; Wait for the next interrupt.
;
sendtxBit:
;  Transmit the current data bit and adjust for next pass.
	mov	A, [txData]		  ; Get the current data.
	or	A, txDataMask	  ; Mask out inputs.
	iowr	Port0_Data	  ; Output the current data bit.
	mov	A, [txData]		  ; Get the current data.
	asr	A			          ; Align next data bit.
	mov	[txData], A		  ; Save adjusted data.
	mov	A, FFh		      ; Fill the accumulator.
	mov	[txBitCount], A ; Write to bit counter.
	jmp	check_tx_bit	  ; Wait for next bit time.
;
sendStop:
;  The data has been sent, now send the stop bit.
	mov	A, FFh		      ; Load stop bit.
	iowr	Port0_Data		; Send stop bit.
	jmp	check_tx_bit	  ; Go to end of transmit.
;
txEnd:
;  The last data bit has been sent.
;  Clean up and return. 
	mov	A, 00h		          ; Clear the accumulator.
	mov	[interrupt_mask], A ; Load into the mask.
	iowr	Global_Interrupt	; Disable all interrupts.
	mov	A, 00h		          ; Load tx Start bit.
	mov	[txBitCount], A	    ; Clear tx bit count.
	mov	[txFrameCount], A	  ; Clear tx frame counter.
	mov	[txEnable], A	      ; Clear the tx enadle flag.
	mov	[rxFrameCount], A	  ; Clear rx frame counter.
	pop	A			              ; Restore the accumulator.
	ret				              ; Return to sender.
;
txWait:
;  Wait for the next 128us interrupt.
	mov	A, 02h		          ; Load 128us ISR Enable value.
	iowr	Global_Interrupt	; Enable 128us ISR.
	jmp	txWait		          ; Loop until 128us Interrupt.
;
;************************************************************************
; RX_Data processing:
; This routine will read in a byte of data from the 8051 UART.
; The receive subroutine is entered whenever the One_mSec_ISR occurs if
; rxEnable is set.
; The received data byte is stored in the receive buffer.
; If stop bit is invalid send a framing error to 8051 and discard data.
;************************************************************************
;
rxRoutine:
;
;  A new 128us interrupt has occurred.
;  Check the frame count and send a bit if required.
	push	A		 	          ; Save the accumulator.
	mov	A, [rxFrameCount] ; Get rx frame count.
	cmp	A, rxStart 	      ; Start bit at frame count=01h.
	jz	getrxStart 	      ; Go get Start bit.
	cmp	A, rxBit0 	      ; Data bit 0 at frame count=05h.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxBit1 	      ; Data bit 1 at frame count=09h.
	jz	getrxBit 	        ; Go get data bit under test.
	cmp	A, rxBit2 	      ; Data bit 2 at frame count=0Ch.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxBit3 	      ; Data bit 3 at frame count=0Fh.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxBit4 	      ; Data bit 4 at frame count=12h.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxBit5 	      ; Data bit 5 at frame count=16h.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxBit6 	      ; Data bit 6 at frame count=19h.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxBit7 	      ; Data bit 7 at frame count=1Ch.
	jz	getrxBit 	        ; Go get data bit.
	cmp	A, rxStop	        ; Stop bit at frame count=1Fh.
	jz	getrxStop	        ; Go get stop bit.
	pop	A		              ; Restore the accumulator.
	ret			              ; Return to caller.
;
;  Read the start bit.
getrxStart:
	iord	Port0_Data	    ; Get data.
	and	A, 80h	          ; Isolate rx data bit.
	jnz	rxAbort	          ; Bad start bit? Go abort.
	pop	A		              ; Restore the accumulator.
	ret			              ; Return to caller.
;
;  Start bit is invalid.
rxAbort:
	mov	A, 00h		        ; Clear the accumulator.
	mov	[rxBitCount], A	  ; Clear rx bit count.
	mov	[rxFrameCount], A	; Clear rx frame count.
	pop	A			            ; Restore the accumulator.
	ret				            ; Return to caller.
;
;  Get the current receive data bit and
;  process into the receive register.	
getrxBit:
	iord	Port0_Data		; Get data.
	and	A, 80h		      ; Isolate rx data bit.
	or	[rxData], A		  ; Add new data bit to register.
	mov	A, [rxBitCount]	; Get count.
	cmp	A, lastrxBit	  ; Check for last data bit.
	jz	rxSave		      ; Exit if last bit.
	inc	[rxBitCount]	  ; Bump the receive bit count.
	mov	A, [rxData]		  ; Get new data value.
	asr	A			          ; Shift data down register.
	and	A, 7Fh		      ; Clear data bit 7.
	mov	[rxData], A		  ; Store adjusted data.
	pop	A			          ; Restore the accumulator.
	ret				          ; Return to caller.
;
;  Time to get the stop bit and check for end of string.	
getrxStop:
;	iord	Port0_Data	    ; Get data.
;	and	A, 80h		        ; Isolate rx stop bit.
	mov	A, Ln_Fd		      ; Get Value of ASCII Line Feed.
	cmp	A, [rxData]		    ; Check for end of data.
	jnz	rxEnd			        ; Get next byte.
	mov	A, 00h		        ; Clear the accumulator.
	mov	[rxEnable], A	    ; Clear rx bit count.
	mov	[rxBitCount], A	  ; Clear rx bit count.
	mov	[rxFrameCount], A	; Clear rx frame count.
	pop	A			            ; Restore the accumulator.
	ret				            ; Return to caller.
;
;  Check that the stop bit is real.
;checkFrame:
;	iord	Port0_Data		  ; Get data.
;	and	A, 80h		        ; Isolate rx data bit.
;	jz	sendFrameError	  ; Framing error detected.
;
;  New character is in register, process it.
rxSave:
;
;  Strip out any ASCII Space characters.
	mov	A, Asc_Space	    ; Get Value of ASCII Space.
	cmp	A, [rxData]		    ; Check for end of data.
	jz	Skip_Char		      ; Get next byte.
;
;  Strip out any ASCII Line Feed characters.
	mov	A, Ln_Fd		      ; Get Value of ASCII Line Feed.
	cmp	A, [rxData]		    ; Check for end of data.
	jz	Skip_Char		      ; Get next byte.
;
;  Save the good ASCII characters in the receive buffer.
	mov	A, [rxData]		    ; Get the good byte of data.
	mov	X, [rxBufPtr]	    ; Point to the next buffer entry.
	mov	[X + rxBuf], A	  ; Save data byte in the receive buffer.
	inc	[rxBufPtr]		    ; Increment the receive buffer pointer.
;
;  Character is on cull list, so skip it.
Skip_Char:
;  Return for the next character;
	inc	[rxBitCount]	; Bump the bit count.
	pop	A			        ; Restore the accumulator.
	ret				        ; Return to caller.
;
;  Receive frame is done.
rxEnd:
	mov	A, 00h		        ; Clear the accumulator.
	mov	[rxBitCount], A	  ; Clear rx bit count.
	mov	[rxFrameCount], A	; Clear rx frame count.
	pop	A			            ; Restore the accumulator.
	ret				            ; Return to caller.
;

;************************************************************************
; This is the routine that is called to enable the receive routine.
;************************************************************************
;
;  Set up to receive the return character string.
getSerial:
	mov	A, 80h		        ; Enable the Port 0 Bit 7
	iowr	Port0_Interrupt	; GPIO interrupt.
;
Start_receive:
;  Enable GPIO interrupts.
  mov	A, GPIO_intMask	    ; Get the GPIO interrupt enable mask.
	iowr	Global_Interrupt	; Enable the Port 0 Bit 7 GPIO interrupt.
;
WaitForStart:
;  Wait for the receive GPIO interrupt.
	mov	A, [rxEnable]	; Get the receive enable flag.
	cmp	A, 00h		    ; Did we get an interrupt?
	jz 	WaitForStart	; Hang around if we didn't.
;
Data_receive:
;  Got the start bit. Enable the 128us interrupt and wait.
;	iowr	Watchdog		      ; Clear watchdog timer
	mov	A, 128us_intMask	  ; Set up the 128 us enable.
	iowr	Global_Interrupt	; Enable it.
	mov	A, [rxEnable]	      ; Get the enable flag.
	cmp	A, 00h		          ; Are we still enabled?
	jnz 	Data_receive	    ; Hang around for the interrupt.
;
Xfer_Done:
	ret				;
;
;************************************************************************
; This is the routine that is called to flush the receive buffer.
;************************************************************************
;
Clear_rxBuf:
;  Clear the receive buffer before sending the next command.
	push	A			      ; Save the accumulator.
	push	X			      ; Save the index register.
	mov	A, 00h		    ; Clear the accumulator.
	mov	[rxBufPtr],	A	; Clear the receive buffer pointer.
;
Clear_rxBuf_Next:
;  Loop and clear all 16 bytes of the receive buffer.
	mov	A, [rxBufPtr]	    ; Load the current receive buffer pointer.
	cmp	A, 10h		        ; Have we done 16?
	jz	Clear_rxBuf_Done	; Yes, we are done.
	mov	A, 00h		        ; Clear the accumulator.
	mov	X, [rxBufPtr]	    ; Load the index register.
	mov	[X + rxBuf], A	  ; Clear the current location.
	inc	[rxBufPtr]		    ; Point to the next byte.
	jmp	Clear_rxBuf_Next	; Do it again.
;
Clear_rxBuf_Done:
	pop	X			; Restore the index register.
	pop	A			; Restore the accumulator.
	ret				; Return to sender.
;
;************************************************************************
; This is the routine that is called to wait after receiving the latest
; character string.
;************************************************************************
;
delay1:
	push	A			                ; Save the accumulator.
	mov	A, FFh		              ; Set loop variable.
	mov	[outerDelayOneCount], A ; Store loop variable.
;
outer_delay1_loop:
	mov	A, 10h		              ; Set loop variable for good sync.
	mov	[innerDelayOneCount], A ; Load the loop count.
      mov	A, 00h		          ; Clear the accumulator.
;
inner_delay1_loop:
	iowr	Watchdog		          ; Clear watchdog timer
	dec	[innerDelayOneCount]	  ; Decrement the inner loop counter.
	cmp	A, [innerDelayOneCount]	; Is it empty?
	jnz	inner_delay1_loop	      ; Not, go do it again.
;
	dec	[outerDelayOneCount]    ; Decrement the outer loop counter.
	cmp	A, [outerDelayOneCount] ; Is it empty?
	jnz	outer_delay1_loop	      ; No, go do it again.
;
	pop	A			; Restore the accumulator.
	ret				; Return to caller.
;
;************************************************************************
; This is the routine that is called to wait between commands.
;************************************************************************
;
delay:
	push  A                   ; Save the accumulator.
	mov  A, FFh               ; Set loop variable
	mov  [outerDelayCount], A ; Store loop variable

outer_delay_loop:
	mov  A, FFh	; Set loop variable for good sync   
	mov  [innerDelayCount], A ;
  mov  A, 00h	              ;
;
inner_delay_loop:
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	nop	;
	iowr  Watchdog		          ; Clear watchdog timer
	dec   [innerDelayCount]	    ; Decrement the inner count.
	cmp   A, [innerDelayCount]  ; Time up?
	jnz   inner_delay_loop      ; Yes, go to the outer loop.
;
	dec  [outerDelayCount]      ; Decrement the outer count.
	cmp  A, [outerDelayCount]   ; Time up?
	jnz  outer_delay_loop       ; No, go through the loops again.
	pop  A                      ; Restore the accumulator.
	ret				                  ; Return to caller.
