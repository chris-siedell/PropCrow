{
======================================
PropCrow
Version 0
March 2018 - Chris Siedell
http://siedell.com/projects/Crow
======================================
}

con
    _clkmode = xtal1 + pll16x
    _xinfreq = 5_000_000

    Flag_SendCheck  = %1_0000_0000

    Flag_Mute       = %0_0100_0000


    'Notes on RxFlags
    '  Shadow-ina is used to hold some receiving flags. On reset it is cleared, and in rxH0 the first
    '    header byte CH0 is or'd into it to save the T flag (command type). From the spec:
    '           |7|6|5|4|3|2|1|0|   Notes: Su is upper bits of payload size. Bit 3 should be avoided since 
    '     ------|---------------|          any increases in max permitted payload size in future specs
    '      CH0  |0|1|0|T|0| Su  |          would use this bit.
    '  Since the upper bytes of _rxByte are guaranteed zero bit 8 will be zero. This means we can
    '    safely use bits 5, 7, and 8 for flags (bit 6 would depend on circumstances).
    RxFlag_CommandType  = %0_0001_0000  'command type, from packet
    RxFlag_WriteByte    = %1_0000_0000  'indicates whether to write previously received byte to hub
    RxFlag_BadPayload   = %0_1000_0000  'indicates whether the payload size exceeds capacity (reportable error)
    RxFlag_Timeout      = %0_0010_0000  'indicates if and interbyte timeout occurred (this prevents auto-recalibration)

    AddressMask     = %0001_1111
    MuteFlag        = %0100_0000

    conMaxPayloadSize = 100     'Must not exceed 2047 (spec limit); must be at least 2 (implementation requirement)
    MaxUserProtocols = 10       'Must not exceed 127 (implementation limit), UserProtocolsTable takes 4*MaxUserProtocols bytes


    PropCrowID  = $80   'must be single byte value




pub new
   
    word[@ControlBlock + 8] := @entry
    word[@ControlBlock + 10] := @entry 
    cognew(@entry, @ControlBlock)

pub chowder(clams, potatoes)
    return 1

dat

{ ControlBlock
}


ControlBlock
long 0
deviceAddress   byte    1
byte 0[3]
word 0
word 0
'DeviceInfoTemplate
deviceInfo0     long    $00000100 | (PropCrowID << 24)                                                      'Crow v1, implementationID = PropCrowID (assumed to be one byte value)
deviceInfo1     long    $00020000 | ((conMaxPayloadSize & $ff) << 8) | ((conMaxPayloadSize & $700) >> 8)    'MaxPayloadLength, 2 admin protocols, numUserProtocols in top byte
deviceInfo2     long    $00000000 | (PropCrowID << 24)                                                      'supports admin protocols numbers 0 and PropCrowID
txScratch       long    0

{ UserProtocols
  User commands are processed by code in other cogs. This table consists of a list of long
    values, where the first word of each long is a supported user protocol number, and the
    second long is the hub address of the control block for processing that protocol's commands.
  The number of defined user protocols is stored in the device info template (top byte of deviceInfo1).
  Summary:
    protocolNumber[i] = word[@UserProtocols + 2*i]
    protocolAddr[i] = word[@UserProtocols + 2*i + 2]
    for i in [0, numUserProtocols)
  The PropCrow implementation allows the user protocols list to change dynamically, but access must be
    locked during the change.
  Order is not important, but there should be no redundancies. If removing an entry be sure to shift the rest down.
}
UserProtocolsTable
long 0[MaxUserProtocols]
BitCountsTable
byte 4, 3, 3, 2, 3, 2, 2, 1, 3, 2, 2, 1, 2, 1, 1, 0


org 0
entry
                                or          outa, txMask
                                or          outa, pin26
                                or          dira, pin26

                                or          dira, pin27

                                mov         addr, par

                                add         addr, #4


                                rdbyte      tmp, addr
                                movs        rxVerifyAddress, tmp 

                                'todo fix
                                movs        rcvyLowCounterMode, #31
                                mov         frqb, #1

                                add         addr, #4
                                rdword      rxPayloadAddr, addr

                                mov         rxPayloadAddrMinusOne, rxPayloadAddr
                                sub         rxPayloadAddrMinusOne, #1

                                add         addr, #2
                                rdword      txPayloadAddr, addr
                                
                                add         addr, #2
                                mov         deviceInfoTemplateAddr, addr

                                add         addr, #7
                                mov         numUserProtocolsAddr, addr

                                add         addr, #5
                                mov         txScratchAddr, addr 

                                add         addr, #4
                                mov         userProtocolsTableAddr, addr

                                { load low bit count table from hub into registers 0-15 }
                                add         addr, #(4*MaxUserProtocols)
                                mov         inb, #16
:loop                           rdbyte      0, addr
                                add         :loop, kOneInDField
                                add         addr, #1
                                djnz        inb, #:loop


                                mov         packetInfo, #0
                                jmp         #UserCommand

{
                                mov         packetInfo, #0
                                wrword      rxPayloadAddr, #0
                                wrword      txPayloadAddr, #2
                                mov         payloadAddr, #0
                                mov         payloadSize, #4
                                jmp         #SendFinalResponse
}
                                jmp         #ReceiveCommand 
                               
{ 
mainLoop                                
                                mov         payloadAddr, addr
                                mov         payloadSize, #4
                                call        #SendFinalAndReturn

                                mov         cnt, cnt
                                add         cnt, shortPause
                                waitcnt     cnt, #0

                                mov         payloadSize, #4
                                call        #SendFinalHeader
                                mov         payloadSize, #1
                                mov         payloadAddr, addr
                                call        #SendPayloadBytes
                                mov         payloadSize, #1
                                call        #SendPayloadBytes
                                mov         payloadSize, #2
                                call        #SendPayloadBytes
                                call        #FinishSending 

                                mov         cnt, cnt
                                add         cnt, pause
                                waitcnt     cnt, #0
                                jmp         #mainLoop

addr                long    60000 
pause               long    4_000_000
shortPause          long    1_000
}


addr                long 0
kOneInDField        long |< 9
tmp                 long 0

pin26               long    |< 26
pin27               long    |< 27

rxPayloadAddr           long 0
rxPayloadAddrMinusOne   long 0
txPayloadAddr           long 0
txScratchAddr           long 0

numUserProtocolsAddr    long 0
userProtocolsTableAddr  long 0
deviceInfoTemplateAddr  long 0

maxPayloadSize          long conMaxPayloadSize
stopBitDuration         long 698
rcvyLowCounterMode      long    $3000_0000 'nop
breakMultiple           long 3602
recoveryTime            long 11104
timeout                 long 80_000
startBitWait            long 337
rxMask                  long |< 31
txMask                  long |< 30

bitPeriod0      long 694
bitPeriod1      long 694
bitPeriod       long 694

kCrowPayloadLimit       long 2047   'The payload size limit imposed by the specification (11 bits in v1 and v2).

{ ReceiveCommand
  This routine contains the receive loop used to receive and process bytes. Processing is done using
    shifted parsing instructions, which are explained in more detail in the "Parsing Instructions" 
    section below.
  This routine supports a minimum bitPeriod of 33.
  There are two exits from this routine: either to RecoveryMode when framing or parsing errors occur, or to
    ReceiveCommandFinish when all bytes of a successfully* parsed packet have been received (this exit
    occurs at rxStartWait, and is determined in the parsing group rxF16C1). (*There are few remaining
    parsing steps performed in ReceiveCommandFinish to completely verify the packet's validity.)
}
ReceiveCommand
                                xor         outa, pin26
                                or          outa, pin27

                                { pre-loop initialization}
                                mov         rxStartWait, rxContinue                 'loop until all bytes received
                                movs        rxMovA, #rxFirstParsingGroup            'prepare shifted parsing code
                                movs        rxMovB, #rxFirstParsingGroup+1
                                movs        rxMovC, #rxFirstParsingGroup+2
                                movs        rxMovD, #rxFirstParsingGroup+3
                                mov         _rxResetOffset, #0
                                mov         _rxWait0, startBitWait                  'prepare wait counter

                                { prepare auto-recalibration }
                                mov         ina, #0                                 'RxFlags - reset, with timeout flag cleared; sh-ina is RxFlags
                                mov         _rxLowBits, #0
                                mov         ctrb, rcvyLowCounterMode
                                mov         phsb, #0
                                test        rxMask, ina                     wz      'z=1 rx pin already low -- missed falling edge todo: do phsb check after instead
                                mov         _rxPrevByte, #$ff                       'so _rxPrevByte contributes no low bits during first pass through loop

                            mov         _rxLowBits2, #0

                        if_nz   waitpne     rxMask, rxMask                          'wait for start bit edge
                        if_nz   add         _rxWait0, cnt
                        if_nz   waitcnt     _rxWait0, bitPeriod0                    'wait to sample start bit (for initial byte only)
                        if_nz   test        rxMask, ina                     wc      'c=1 framing error; c=0 continue, with parser reset
                    if_z_or_c   jmp         #RecoveryMode                           '...exit for framing error or missed falling edge

                            mov         tmp, phsb
                            wrlong      tmp, #0 

                                { the receive loop -- c=0 reset parser}

'bit0 - 34 clocks
rxBit0                          waitcnt     _rxWait0, bitPeriod1
                                testn       rxMask, ina                     wz
                            add         _rxLowBits2, #1
                    if_nz   add         _rxLowBits2, #1
                                muxz        _rxByte, #%0000_0001
                                mov         _rxWait1, _rxWait0                      'Wait 2
                                mov         _rxWait0, startBitWait                  'Wait 3
                        if_nc   mov         _rxF16L, #0                             'F16 1 - see page 90
                        if_c    add         _rxF16L, _rxPrevByte                    'F16 2
                        if_c    cmpsub      _rxF16L, #255                           'F16 3

'bit1 - 34 clocks
rxBit1                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                    if_nz   add         _rxLowBits2, #1
                                muxz        _rxByte, #%0000_0010
                        if_nc   mov         inb, #0                                 'F16 4 - during receiving, sh-inb is rxF16U
                        if_c    add         inb, _rxF16L                            'F16 5
                        if_c    cmpsub      inb, #255                               'F16 6
                        if_nc   mov         _rxOffset, _rxResetOffset               'Shift 1 - go back to first parsing group on reset (see page 93)
                                subs        _rxResetOffset, _rxOffset               'Shift 2 - adjust reset offset

'bit 2 - 34 clocks
rxBit2                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                    if_nz   add         _rxLowBits2, #1
                                muxz        _rxByte, #%0000_0100
                                adds        rxMovA, _rxOffset                       'Shift 3 - (next four) offset addresses for next parsing group
                                adds        rxMovB, _rxOffset                       'Shift 4
                                add         _rxLowBits, #1                          'Auto-Recal 1 - account for start bit (of curr byte)
                                movs        rxAddLowerNibble, _rxPrevByte           'Auto-Recal 2 - determine low bit count in lower nibble (of prev byte)
                                andn        rxAddLowerNibble, #%1_1111_0000         'Auto-Recal 3

'bit 3 - 30 clocks
rxBit3                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                    if_nz   add         _rxLowBits2, #1
                                muxz        _rxByte, #%0000_1000
                                adds        rxMovC, _rxOffset                       'Shift 5
                                adds        rxMovD, _rxOffset                       'Shift 6
                                mov         _rxOffset, #4                           'Shift 7 - restore default offset (must be done before shifted instructions)
rxMovA                          mov         rxShiftedA, 0-0                         'Shift 8 - (next four) shift parsing instructions into place

'bit 4 - 34 clocks
rxBit4                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                    if_nz   add         _rxLowBits2, #1
                                muxz        _rxByte, #%0001_0000
rxMovB                          mov         rxShiftedB, 0-0                         'Shift 9
rxMovC                          mov         rxShiftedC, 0-0                         'Shift 10
rxMovD                          mov         rxShiftedD, 0-0                         'Shift 11
                                test        ina, #RxFlag_WriteByte          wc      'Write 1 - c=1 => write byte; sh-ina is RxFlags
                        if_c    add         _rxAddr, #1                             'Write 2 - increment address (pre-increment saves an instruction)

'bit 5 - 33 clocks
rxBit5                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                    if_nz   add         _rxLowBits2, #1
                        if_c    wrbyte      _rxPrevByte, _rxAddr                    'Write 3 - wrbyte takes all remaining slots

'bit 6 - 34 clocks
rxBit6                          waitcnt     _rxWait1, bitPeriod1
                                test        rxMask, ina                     wc
                    if_nc   add         _rxLowBits2, #1
                                muxz        _rxByte, #%0010_0000
                                muxc        _rxByte, #%0100_0000
                                sub         _rxCountdown, #1                wz      'Countdown - used by parsing code to determine when F16 follows payload bytes
rxShiftedA                      long    0-0                                         'Shift 12
rxShiftedB                      long    0-0                                         'Shift 13
rxAddLowerNibble                add         _rxLowBits, 0-0                         'Auto-Recal 4

'bit 7 - 34 clocks
rxBit7                          waitcnt     _rxWait1, bitPeriod0
                                test        rxMask, ina                     wc
                    if_nc   add         _rxLowBits2, #1
                                muxc        _rxByte, #%1000_0000
                                shr         _rxPrevByte, #4                         'Auto-Recal 5 - determine low bit count in upper nibble
                                movs        rxAddUpperNibble, _rxPrevByte           'Auto-Recal 6
rxShiftedC                      long    0-0                                         'Shift 14
rxShiftedD                      long    0-0                                         'Shift 15
rxAddUpperNibble                add         _rxLowBits, 0-0                         'Auto-Recal 7

rxStopBit                       waitcnt     _rxWait1, bitPeriod0                    'see page 98
                                testn       rxMask, ina                     wz      'z=0 framing error

rxStartWait                     long    0-0                                         'wait for start bit, or exit loop
                        if_z    add         _rxWait0, cnt                           'Wait 1

'start bit - 34 clocks
rxStartBit              if_z    waitcnt     _rxWait0, bitPeriod0
                        if_z    test        rxMask, ina                     wz      'z=0 framing error
                        if_z    mov         phsa, _rxWait0                          'Timeout 1 - sh-phsa used as scratch since ctra should be off
                        if_z    sub         phsa, _rxWait1                          'Timeout 2 - see page 98 for timeout notes
                        if_z    cmp         phsa, timeout                   wc      'Timeout 3 - c=0 reset, c=1 no reset
                        if_z    mov         _rxPrevByte, _rxByte                    'Handoff
                if_z_and_nc     mov         ina, #RxFlag_Timeout                    'RxFlags - reset rx flags with timeout flag set        
                        if_z    jmp         #rxBit0

                    { fall through to recovery mode for framing errors }


{ RecoveryMode
  When framing or parsing errors occur the implementation enters recovery mode. In this mode the implementation
    waits for the rx line to be in high-idle for a certain period of time before attempting to receive another
    command. If the line is low for long enough then the implementation determines that a break condition has occurred.
  See page 99.
}
RecoveryMode
                                mov         ctrb, rcvyLowCounterMode
                                mov         cnt, recoveryTime
                                add         cnt, cnt
                                mov         _rcvyPrevPhsb, phsb                     'first interval always recoveryTime+1 counts, so at least one loop for break 
                                mov         inb, breakMultiple                      'sh-inb is countdown to break detection
rcvyLoop                        waitcnt     cnt, recoveryTime
                                mov         _rcvyCurrPhsb, phsb
                                cmp         _rcvyPrevPhsb, _rcvyCurrPhsb    wz      'z=1 line always high, so exit
                        if_z    mov         ctrb, #0                                'ctrb must be off before exit
                        if_z    jmp         #ReceiveCommand                         '...exit: line is idle -- ready for next command
                                mov         par, _rcvyPrevPhsb
                                add         par, recoveryTime
                                cmp         par, _rcvyCurrPhsb              wz      'z=0 line high at some point
                        if_nz   mov         inb, breakMultiple                      'reset break detection countdown
                                mov         _rcvyPrevPhsb, _rcvyCurrPhsb
                                djnz        inb, #rcvyLoop
                                mov         ctrb, #0                                'ctrb must be off before exit

                        { fall through when a break is detected }


{ DetectBaud
  PropCrow interprets the break condition as a command to enter baud detection mode.
}
DetectBaud

BreakHandler
                                waitpeq     rxMask, rxMask                          'wait for break to end
                                { todo }
                                jmp         #ReceiveCommand


{ Parsing Instructions, used by ReceiveCommand
  There are four parsing instructions per received byte, labelled A-D. These instructions are shifted
    into the receive loop at rxShiftedA-D. Each group must take four registers with no gaps between
    them (use nops if necessary).
  rxFirstParsingGroup identifies the first parsing group to be executed on parser reset.
  Instructions A and B are executed consecutively during the interval after bit[6] has been sampled, but
    before bit[7] is sampled. Instructions C and D are executed consecutively after bit[7], but before
    the stop bit. (This arrangement was found most conducive for parsing a Crow header.)
  _rxOffset determines the parsing group to be executed for the next byte. It is automatically set to
    four before instruction A, which means the default is to execute the following parsing group
    during the next byte. Parsing code can change _rxOffset to change the next group (it is a signed
    value, and should always be a multiple of four).
  The RxFlag_WriteByte bit of sh-ina (RxFlags) determines whether the current byte will be written to the hub.
    This flag is automatically cleared on parser reset, and it must be manually set or cleared after that.
  If RxFlag_WriteByte is set then the byte will be written to ++_rxAddr. Note that _rxAddr is automatically
    incremented BEFORE writing the byte (_rxAddr is not incremented unless the byte will be written). This
    means _rxAddr must initially be set to the desired address minus one. _rxAddr is undefined on parser reset.
  Before instruction A, _rxCountdown is decremented and the z flag indicates whether the countdown is
    zero. _rxCountdown is undefined on parser reset.
  Before instruction A the c flag is set to bit[6]. Before instruction C the c flag is set to bit[7].
  Parsing code may change the z and c flags (but remember c will be set to bit[7] between B and C).
  Parsing code MUST NOT change the value of _rxByte -- this will cause the checksums to fail.
  Parsing code MUST NOT change _rxPrevByte -- this will cause auto-recalibration to fail.
  The F16 checksums are automatically calculated in the receive loop, but checking their validity
    must be done by the parsing code. This must be done in the parsing group immediately after F16 C1 is
    received (which will always be a payload byte, except for the very last checkbyte of the packet,
    which is verified in ReceiveCommandFinish). Immediately after F16 C1 is received and processed
    both running checksums (_rxF16U and _rxF16L) should be zero.
  The parsing code must ensure that the payload buffer is not exceeded. The RxFlag_BadPayload is used
    for that purpose (it is cleared on reset).
  Summary:
    On parser reset:
      parsing group rxFirstParsingGroup is selected
      sh-ina (RxFlags) is cleared       (so turn off writing to hub, and reset excessive payload size flag)
      _rxF16U (sh-inb) := _rxF16L := 0           (F16 checksums are reset, as per Crow specification)
      _rxCountdown = <undefined>        (so z will be undefined at rxFirstParsingGroup instruction A) 
      _rxPrevByte = <undefined>
      _rxAddr = <undefined>
    Before A and B:
      _rxByte (READ-ONLY) is complete to bit[6], but bit[7] is undefined (upper bytes are zero)
      _rxPrevByte (READ-ONLY) is the byte received before this one (upper bytes are zero)
      _rxF16U (sh-inb) and _rxF16L (READ-ONLY) are calculated up to the previous byte
      _rxCountdown := _rxCountdown - 1
      _rxOffset := 4                    (this is a signed value, and it determines the next group executed)
      z := _rxCountdown==0
      c := bit[6]
    Before C and D:
      _rxByte (READ-ONLY) is complete (upper bytes are zero)
      _rxPrevByte (READ-ONLY) has been shifted down by 4 bits
      z is not changed, so it maintains whatever value it had after B
      c := bit[7]
  See "The Command Header" section of "Crow Specification v1.txt". See also page 113.
  The parsing groups are labelled by the byte being received when they execute.
}
rxFirstParsingGroup
rxH0                            test        _rxByte, #%0010_1000        wz      'A - z=1 if reserved bits 3 and 5 are zero, as required
                if_nc_or_nz     jmp         #RecoveryMode                       ' B - ...exit for bad reserved bits; c (bit 6) must be 1
                        if_c    jmp         #RecoveryMode                       ' C - ...exit for bad reserved bit; c (bit 7) must be 0
                                or          ina, _rxByte                        ' D - save T flag in sh-ina (RxFlags); or'd to preserve other flags; see RxFlags notes 
rxH1                            mov         payloadSize, _rxPrevByte            'A - extract payload size
                                and         payloadSize, #$7                    ' B
                                shl         payloadSize, #8                     ' C
                                or          payloadSize, _rxByte                ' D
rxH2                            mov         _rxRemaining, payloadSize           'A - _rxRemaining keeps track of how many payload bytes are left to receive
                                mov         _rxAddr, rxPayloadAddrMinusOne     ' B - reset address for writing to hub
                                mov         par, #0                             ' C - set implicit protocol; sh-par used to store protocol
                                mov         token, _rxByte                      ' D
rxH3                            test        _rxByte, #%0010_0000        wz      'A - z=1 if reserved bit 5 is zero, as required
                        if_nz   jmp         #RecoveryMode                       ' B - ...exit for bad reserved bit
                                mov         packetInfo, _rxByte                 ' C - preserve Crow address and mute flag
                        if_nc   mov         _rxOffset, #12                      ' D - skip rxH4 and rxH5 if using implicit protocol
rxH4                            nop                                             'A - spacer nop
                                nop                                             ' B - spacer nop
                                mov         par, _rxByte                        ' C
                                shl         par, #8                             ' D
rxH5                            nop                                             'A - spacer nop
                                nop                                             ' B - spacer nop
                                nop                                             ' C - spacer nop
                                or          par, _rxByte                        ' D
rxF16C0                         andn        ina, #RxFlag_WriteByte              'A - turn off writing to hub (don't write F16 bytes); sh-ina is RxFlags
                                mov         _rxCountdown, _rxRemaining          ' B - _rxCountdown used to keep track of payload bytes left in chunk 
                                max         _rxCountdown, #128                  ' C - chunks are limited to 128 data bytes
                                sub         _rxRemaining, _rxCountdown          ' D - _rxRemaining is number of payload bytes after the coming chunk
rxF16C1                         add         _rxCountdown, #1            wz      'A - undo automatic decrement; check if _rxCountdown==0 (next chunk empty)
                        if_z    mov         rxStartWait, rxExit                 ' B - ...exit receive loop if no bytes in next chunk (all bytes received)
                                cmp         payloadSize, maxPayloadSize wz, wc  ' C - check if command payload size exceeds buffer capacity
                if_nc_and_nz    or          ina, #RxFlag_BadPayload             ' D - ...if so, set flag (see rxP_Repeat); sh-ina is RxFlags
rxP_VerifyF16                   or          ina, #RxFlag_WriteByte              'A - turn on writing to hub; sh-ina is RxFlags
                        if_z    subs        _rxOffset, #12                      ' B - if _rxCountdown==0 then chunk's payload bytes done, go to rxF16C0
                                or          inb, _rxF16L                wz      ' C - should have F16U == F16L == 0; sh-inb is rxF16U
                        if_nz   jmp         #RecoveryMode                       ' D - ...exit for bad checksums
rxP_Repeat              if_z    subs        _rxOffset, #16                      'A - go to rxF16C0 if all of chunk's payload bytes are received
                        if_nz   subs        _rxOffset, #4                       ' B - ...otherwise, repeat this group
                                test        ina, #RxFlag_BadPayload     wc      ' C - check if payload size exceeds capacity (from rxF16C1); sh-ina is RxFlags
                        if_c    mov         _rxAddr, rxPayloadAddrMinusOne      ' D - ...if so, keep resetting address to prevent overrun (command discarded anyway)



{ Receive Loop Continue / Exit Instructions
  These instructions are shifted to rxStartWait in the receive loop to either receive more bytes
    or exit the loop and finish processing the packet. }
rxContinue              if_z    waitpne     rxMask, rxMask
rxExit                  if_z    jmp         #ReceiveCommandFinish


{ ReceiveCommandFinish
  This code runs when all  }
ReceiveCommandFinish
                                mov         ctrb, #0                                'turn off low bit counter

                                { verify checksums for last byte }
                                add         _rxF16L, _rxByte                        'compute F16L for last byte
                                cmpsub      _rxF16L, #255                           '(computing F16U unnecessary since it should be zero)
                                or          inb, _rxF16L                    wz
                        if_nz   jmp         #RecoveryMode                           '...bad F16

                                { verify the address }
                                mov         cnt, packetInfo                         'sh-cnt used for scratch; packetInfo is CH3
                                and         cnt, #AddressMask               wz      'z=1 broadcast address (0)
                                test        packetInfo, #MuteFlag           wc      'c=1 mute response
                    if_z_and_nc jmp         #RecoveryMode                           '...broadcast must mute (invalid packet)
rxVerifyAddress         if_nz   cmp         cnt, #0-0                       wz      'verify non-broadcast address; s-field set at initialization
                        if_nz   jmp         #ReceiveCommand                         '...wrong non-broadcast address

                                { at this point the packet has no non-reportable errors, so recovery mode is not used;
                                    it is also correctly addressed, so error responses may be sent for reportable errors (it is safe
                                    to call the sending code if the command was broadcast -- responses are muted) }

                                { auto-recalibration }
                                test        ina, #RxFlag_Timeout            wc      'sh-ina is RxFlags
                        if_c    jmp         #:checkForBadPayload                    '...skip if timeout occurred -- the timings can't be used
                              
                                'determine number of low bits for last byte 

                                mov         inb, #8
:loop                           shr         _rxByte, #1                     wc
                        if_nc   add         _rxLowBits, #1
                                djnz        inb, #:loop

                            mov         tmp, phsb
                            wrlong      tmp, #4
                            wrlong      _rxLowBits, #8
                            wrlong      _rxLowBits2, #12 
                            wrlong      _rxByte, #16
                            wrlong      rxAddLowerNibble, #20
                            wrlong      rxAddUpperNibble, #24


                                { check if payload size exceeded capacity -- a reportable error condition }
:checkForBadPayload             test        ina, #RxFlag_BadPayload         wc      'sh-ina is RxFlags
                        if_c    jmp         #ReceiveCommand

                                { check command type, exit if user command }
                                test        ina, #RxFlag_CommandType        wc      'c=1 user command; sh-ina is RxFlags 
                        if_c    jmp         #UserCommand
                                
                                { check admin protocol, exit if supported }
                                cmp         par, #0                         wz      'sh-par is protocol (from rxH2 or rxH5)
                        if_z    jmp         #UniversalAdminCommand
                                cmp         par, #PropCrowID                wz      'PropCrowID assumed to be 9-bit or less
                        if_z    jmp         #PropCrowAdminCommand

                                jmp         #ReceiveCommand


{ UniversalAdminCommand
  The universal admin commands (admin protocol 0) are defined in "Crow Specification v1.txt".
  There are two commands: ping, and getDeviceInfo.
}
UniversalAdminCommand

                                xor         outa, pin26
                                andn          outa, pin27

                                { admin protocol 0 with no payload is ping }
                                cmp         payloadSize, #0                 wz      'z=1 ping command
                        if_nz   jmp         #:getDeviceInfo
                                jmp         #SendFinalResponse                      'send ping response (payloadSize==0), then go to ReceiveCommand

                                { other admin protocol 0 command, getDeviceInfo, has 0x00 as payload }
:getDeviceInfo                  cmp         payloadSize, #1                 wz      'z=0 wrong payload size for getDeviceInfo (1)
                        if_z    rdbyte      cnt, rxPayloadAddr                      'load payload byte into sh-cnt
                        if_z    cmp         cnt, #$00                       wz      'z=0 wrong payload for getDeviceInfo
                        if_nz   jmp         #ReceiveCommand                         '...command not getDeviceInfo or ping

                                { perform getDeviceInfo }

                                call        #LockSharedAccess                       'the user protocols list is allowed to change

                                rdbyte      _tmpCount, numUserProtocolsAddr         'get number of user protocols

                                mov         payloadSize, _tmpCount                  'response payload size is 12 + 2*numUserProtocols (assuming 2 admin protocols)
                                shl         payloadSize, #1
                                add         payloadSize, #12

                                call        #SendFinalHeader

                                mov         payloadAddr, deviceInfoTemplateAddr     'send first 12 bytes of device info response
                                mov         payloadSize, #12
                                call        #SendPayloadBytes

                                cmp         _tmpCount, #0                   wz
                        if_z    jmp         #:finish

                                mov         payloadAddr, userProtocolsTableAddr     'send the user protocol numbers directly from the table
                                sub         payloadAddr, #3

:loop                           add         payloadAddr, #4                         'MSB             
                                mov         payloadSize, #1
                                call        #SendPayloadBytes
                                sub         payloadAddr, #2                         'LSB
                                mov         payloadSize, #1
                                call        #SendPayloadBytes

                                djnz        _tmpCount, #:loop       

:finish                         call        #FinishSending
 
                                call        #UnlockSharedAccess
                                
                                jmp         #ReceiveCommand


{ PropCrowAdminCommand

}
PropCrowAdminCommand
                                mov         payloadAddr, rxPayloadAddr
                                jmp         #SendFinalResponse

{ UserCommand
}
UserCommand

'                                mov         payloadAddr, rxPayloadAddr


                                mov         inb, #16

                                movd        :loop, #0
                                mov         addr, #28

:loop                           wrlong      0, addr
                                add         $-1, kOneInDField
                                add         addr, #4
                                djnz        inb, #:loop


                                mov         payloadAddr, #0
                                mov         payloadSize, #92
                                
                                jmp         #SendFinalResponse

{ LockSharedAccess
  A call to LockSharedAcccess must be followed by a call to UnlockSharedAccess.
}
LockSharedAccess
                                nop
LockSharedAccess_ret            ret

{ UnlockSharedAccess
}
UnlockSharedAccess
                                nop
UnlockSharedAccess_ret          ret



{ txSendBytes }
{ Helper routine  used to send bytes. It also updates the running F16 checksum. It assumes
    the tx pin is already an output. Bytes are sent from the hub.
  This lowest bitPeriod supported by this routine is 32 or 33 clocks (32 clocks requires that
    the stopBitPeriod be a multiple of 2 to avoid worst case timing for hub reads).
  Usage:    mov     _txAddr, <hub address of bytes>
            mov     _txCount, <number to send != 0>
            call    #txSendBytes
  After retuning _txCount will be zero and _txAddr will point to the address immediately
    after the last byte sent.
}
txSendBytes
                                rdbyte      _txByte, _txAddr
                                
                                mov         cnt, cnt
                                add         cnt, #9

:txByteLoop                     waitcnt     cnt, bitPeriod                      'start bit
                                andn        outa, txMask

                                add         _txF16L, _txByte                    'F16 calculation
                                cmpsub      _txF16L, #255
                                add         _txF16U, _txF16L
                                cmpsub      _txF16U, #255

                                shr         _txByte, #1                 wc
                                waitcnt     cnt, bitPeriod                      'bit0
                                muxc        outa, txMask

                                mov         inb, #6
                                add         _txAddr, #1

:txBitLoop                      shr         _txByte, #1                 wc
                                waitcnt     cnt, bitPeriod                      'bits1-6
                                muxc        outa, txMask
                                djnz        inb, #:txBitLoop
            
                                shr         _txByte, #1                 wc
                                
                                waitcnt     cnt, bitPeriod                      'bit7
                                muxc        outa, txMask

                                rdbyte      _txNextByte, _txAddr

                                waitcnt     cnt, stopBitDuration                'stop bit
                                or          outa, txMask

                                mov         _txByte, _txNextByte

                                djnz        _txCount, #:txByteLoop

                                waitcnt     cnt, #0                             'ensure line is high for a full stop bit duration
txSendBytes_ret                 ret 


{ SendFinalHeader, SendIntermediateHeader (Partial Sending Routines)
  The partial sending routines exist to allow sending payload bytes from multiple random
    locations of hub RAM without buffering them first. If sending from a single contiguous block
    of hub RAM then it is easier to use the Complete Sending Routines.
  Usage:    mov     payloadSize, <number of bytes total in payload>
            call    #SendFinalHeader
      <or>  call    #SendIntermediateHeader
      <then, if there is a payload -- repeat until all bytes sent>
            mov     payloadSize, <number of bytes in payload fragment>
            mov     payloadAddr, <address of payload fragment>
            call    #SendPayloadBytes
      <finally>
            call    #FinishSending
}
SendFinalHeader
                                movs        txApplyTemplate, #$90
                                jmp         #txPerformChecks
SendIntermediateHeader
                                movs        txApplyTemplate, #$80

                                { checks: ensure not muted, and ensure payload size is within buffer size }
txPerformChecks                 test        packetInfo, #Flag_Mute           wc 
                        if_c    jmp         SendHeader_ret
                                max         payloadSize, kCrowPayloadLimit      'do not allow payloadSize to exceed spec limit

                                { compose header bytes RH0-RH2 }
                                mov         par, payloadSize                    'sh-par used for scratch
                                shr         par, #8                             '(assumes payloadSize does not exceed spec limit)
txApplyTemplate                 or          par, #0-0
                                mov         _txAddr, txScratchAddr                      
                                wrbyte      par, _txAddr                        'RH0
                                add         _txAddr, #1
                                wrbyte      payloadSize, _txAddr                'RH1
                                add         _txAddr, #1
                                wrbyte      token, _txAddr                      'RH2

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

                                { retain line }
txRetainLine                    or          dira, txMask

                                { send RH0-RH2 }
                                mov         _txAddr, txScratchAddr
                                mov         _txCount, #3
                                call        #txSendBytes

                                { send RH3-RH4 (the header F16) }
                                call        #txSendAndResetF16

                                { prepare for sending payload bytes }
                                andn        packetInfo, #Flag_SendCheck              'the SendCheck flag is set when payload bytes are sent
                                mov         _txMaxChunkRemaining, #128          'the maximum number of bytes for a full chunk (the last may be partial)
SendHeader_ret
SendFinalHeader_ret
SendIntermediateHeader_ret      ret
    

{ SendPayloadBytes (Partial Sending Routine)
  This routine sends payload bytes for an response packet that has been started with a
    call to SendFinalHeader or SendIntermediateHeader.
  Note that the total number of bytes to send must still be known before sending the header.
    The total sum of bytes sent using one or more SendPayloadBytes calls must exactly match the
    payloadSize passed to the header sending routine -- if it does not, then the Crow host (i.e. PC)
    will experience some sort of error (e.g. timeout, unexpected number of bytes, bad checksum).
  Usage:
            mov     payloadSize, <number of bytes to send with this call, may be zero>
            mov     payloadAddr, <base address of bytes to send>
            call    #SendPayloadBytes
  After this call payloadSize will be zero and payloadAddr will point to the address after the last byte sent.
}
SendPayloadBytes
                                test        packetInfo, #Flag_Mute               wc      'skip if responses muted
                        if_c    jmp         SendPayloadBytes_ret
:loop
                                mov         _txCount, payloadSize           wz
                        if_z    jmp         SendPayloadBytes_ret                    'exit: nothing to send
                                max         _txCount, _txMaxChunkRemaining
                                sub         payloadSize, _txCount
                                sub         _txMaxChunkRemaining, _txCount  wz      'z=0 implies _txCount < _txMaxChunkRemaining, and also that
                                                                                    ' payloadSize is now zero -- in other words, this is the last bit of payload data
                                                                                    ' to send with this call, but the chunk is not full
                                mov         _txAddr, payloadAddr

                                call        #txSendBytes
                                or          packetInfo, #Flag_SendCheck                  'if any payload bytes have been sent then a checksum must follow eventually

                                mov         payloadAddr, _txAddr

                        if_nz   jmp         SendPayloadBytes_ret                    'exit: chunk is not finished, but all bytes for this call have been sent 

                                { chunk is finished, but there may be more payload bytes to send, so send checksum now }

                                call        #txSendAndResetF16

                                { prep for next chunk }
                                andn        packetInfo, #Flag_SendCheck
                                mov         _txMaxChunkRemaining, #128
 
                                jmp         #:loop 

SendPayloadBytes_ret            ret


{ FinishSending (Partial Sending Routine)
  This routine finishes the response packet.
  This routine MUST be called after a call to SendFinalHeader or SendIntermediateHeader,
    even if there are no payload bytes.
}
FinishSending
                                test        packetInfo, #Flag_Mute               wc      'skip if responses muted
                        if_c    jmp         FinishSending_ret
                                test        packetInfo, #Flag_SendCheck          wc      'send final payload checksum if necessary
                        if_c    call        #txSendAndResetF16
txReleaseLine                   andn        dira, txMask                            'this instruction may be deleted in some circumstances (along
FinishSending_ret               ret                                                 ' with txRetainLine) -- see "PropCrow User Guide.txt"


{ Complete Sending Routines 
  These routines require that the entire payload be in a contiguous block of hub ram.
  Usage:    mov         payloadSize, <num bytes of payload>
            mov         payloadAddr, <hub address of payload>
            call        #SendFinalAndReturn
       <or> call        #SendIntermediate
       <or> jmp         #SendFinalResponse
  Both payloadSize and payloadAddr are modified by these routines. 
}
SendFinalResponse

                                movs        Send_ret, #ReceiveCommand
SendFinalAndReturn
                                movs        txApplyTemplate2, #$90
                                jmp         #txPerformChecks2
SendIntermediate
                                movs        txApplyTemplate2, #$80

                                { checks: ensure not muted, and ensure payload size is within buffer size }
txPerformChecks2                test        packetInfo, #Flag_Mute              wc      'c=1 muted
                        if_c    jmp         Send_ret
                                max         payloadSize, maxPayloadSize

                                { compose header bytes RH0-RH2 }
                                mov         par, payloadSize                            'sh-par used to compose first byte of header
                                shr         par, #8                                     'assumes payloadSize <= 2047
txApplyTemplate2                or          par, #0-0
                                mov         _txAddr, txScratchAddr                      
                                wrbyte      par, _txAddr
                                add         _txAddr, #1
                                wrbyte      payloadSize, _txAddr
                                add         _txAddr, #1
                                wrbyte      token, _txAddr

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

                                { retain line }
                                or          dira, txMask

                                { send RH0-RH2 }
                                mov         _txAddr, txScratchAddr
                                mov         _txCount, #3
                                call        #txSendBytes

                                { send RH3-RH4 (the header F16) }
                                call        #txSendAndResetF16

                                { send packet body (chunks of payload bytes with checksums) }
txPayloadLoop                   mov         _txCount, payloadSize               wz      'z=1 => nothing left to send
                        if_z    jmp         #txLoopExit
                                max         _txCount, #128                              'next chunk size (max of 128 bytes)
                                sub         payloadSize, _txCount
                                mov         _txAddr, payloadAddr
                                call        #txSendBytes
                                mov         payloadAddr, _txAddr                        'preserve payload address for next chunk
                                call        #txSendAndResetF16
                                jmp         #txPayloadLoop
txLoopExit
                                andn        dira, txMask
Send_ret
SendFinalAndReturn_ret
SendIntermediate_ret            ret
    
            

{ txSendAndResetF16
  Helper routine to send the current F16 checksum (upper first, then lower). It 
    also resets the checksum after sending. }
txSendAndResetF16
                                { save F16 to hub }
                                mov         _txAddr, txScratchAddr
                                wrbyte      _txF16U, _txAddr
                                add         _txAddr, #1
                                mov         _txCount, #2                        'sending prep
                                wrbyte      _txF16L, _txAddr
                            
                                { send F16 }
                                mov         _txAddr, txScratchAddr
                                call        #txSendBytes

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

txSendAndResetF16_ret           ret






protocol                    res
token                       res
packetInfo                  res

payloadSize     res
payloadAddr     res

_tmp            res

_rcvyPrevPhsb
_rcvyCurrPhsb

_txMaxChunkRemaining    res
_txAddr         res
_txCount        res
_txNextByte     res
_txByte         res
_txF16L         res
_txF16U         res

_rxLowBits2         res
_rxLowBits          res
_rxByte             res 
_rxPrevByte         res
_rxF16L             res
_rxOffset           res
_rxResetOffset      res
_rxWait0            res
_rxWait1            res
_rxCountdown        res
_rxAddr             res
_rxRemaining        res


_tmpCount       res

fit 496


