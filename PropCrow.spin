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
    Flag_WriteByte  = %0_1000_0000

    Flag_Mute       = %0_0100_0000
  


pub new
    
    cognew(@entry, 0)


dat
org 0
entry
                                or          dira, txMask
                                
                                'set token to 178
                                mov         0, #178
                                mov         _tmp, hubScratch
                                add         _tmp, #2
                                wrbyte      0, _tmp
ReceiveCommand
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
                                { pre-loop initialization}
                                mov         rxStartWait, rxContinue                 'loop until all bytes received
                                movs        rxMovA, #rxFirstParsingGroup            'prepare shifted parsing code
                                movs        rxMovB, #rxFirstParsingGroup+1
                                movs        rxMovC, #rxFirstParsingGroup+2
                                movs        rxMovD, #rxFirstParsingGroup+3
                                mov         _rxResetOffset, #0
                                mov         _rxWait0, startBitWait                  'prepare wait counter
                                waitpne     rxMask, rxMask                          'wait for start bit edge
                                add         _rxWait0, cnt
                                waitcnt     _rxWait0, bitPeriod0                    'wait to sample start bit (for initial byte only)
                                test        rxMask, ina                     wc      'c=1 framing error; c=0 continue, with parser reset
                        if_c    jmp         #RecoveryMode

                                { the receive loop -- c=0 reset parser}

rxBit0                          waitcnt     _rxWait0, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxz        _rxByte, #%0000_0001
                                mov         _rxWait1, _rxWait0                      'Wait 2
                                mov         _rxWait0, startBitWait                  'Wait 3
                        if_nc   mov         _rxF16L, #0                             'F16 1 - see page 90
                        if_c    add         _rxF16L, _rxPrevByte                    'F16 2

rxBit1                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                                muxz        _rxByte, #%0000_0010
                        if_c    cmpsub      _rxF16L, #255                           'F16 3
                        if_nc   mov         _rxF16U, #0                             'F16 4
                        if_c    add         _rxF16U, _rxF16L                        'F16 5
                        if_c    cmpsub      _rxF16U, #255                           'F16 6

rxBit2                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxz        _rxByte, #%0000_0100
                        if_nc   mov         _rxOffset, _rxResetOffset               'Shift 1 - go back to first parsing group on reset (see page 93)
                                subs        _rxResetOffset, _rxOffset               'Shift 2 - adjust reset offset
                                adds        rxMovA, _rxOffset                       'Shift 3 - (next four) offset addresses for next parsing group
                                adds        rxMovB, _rxOffset                       'Shift 4

rxBit3                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                                muxz        _rxByte, #%0000_1000
                                adds        rxMovC, _rxOffset                       'Shift 5
                                adds        rxMovD, _rxOffset                       'Shift 6
                                mov         _rxOffset, #4                           'Shift 7 - restore default offset (must be done before shifted instructions)
rxMovA                          mov         rxShiftedA, 0-0                         'Shift 8 - (next two) shift parsing instructions A and B into place

rxBit4                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxz        _rxByte, #%0001_0000
rxMovB                          mov         rxShiftedB, 0-0                         'Shift 9
                        if_nc   andn        _rxFlags, #Flag_WriteByte               'Write 1 - clear write flag on reset
                                test        _rxFlags, #Flag_WriteByte       wc      'Write 2 - c=1 => write byte
                        if_c    add         _rxAddr, #1                             'Write 3 - increment address (pre-increment by necessity)

rxBit5                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                        if_c    wrbyte      _rxPrevByte, _rxAddr                    'Write 4 - wrbyte takes all five remaining slots

rxBit6                          waitcnt     _rxWait1, bitPeriod1
                                test        rxMask, ina                     wc
                                muxz        _rxByte, #%0010_0000
                                muxc        _rxByte, #%0100_0000
                                sub         _rxCountdown, #1                wz      'Countdown - used by parsing code to determine when F16 follows payload bytes
rxShiftedA                      long    0-0                                         'Shift 10 - (next two) the shifted parsing instructions A and B
rxShiftedB                      long    0-0                                         'Shift 11

rxBit7                          waitcnt     _rxWait1, bitPeriod0
                                test        rxMask, ina                     wc
                                muxc        _rxByte, #%1000_0000
rxMovC                          mov         rxShiftedC, 0-0                         'Shift 12 - (next two) shift parsing instructions C and D into place
rxMovD                          mov         rxShiftedD, 0-0                         'Shift 13
rxShiftedC                      long    0-0                                         'Shift 14 - (next two) the shifted parsing instructions C and D
rxShiftedD                      long    0-0                                         'Shift 15

rxStopBit                       waitcnt     _rxWait1, bitPeriod0                    'see page 98
                                testn       rxMask, ina                     wz      'z=0 framing error

rxStartWait                     long    0-0                                         'wait for start bit, or exit loop
                        if_z    add         _rxWait0, cnt                           'Wait 1

rxStartBit              if_z    waitcnt     _rxWait0, bitPeriod0
                        if_z    test        rxMask, ina                     wz      'z=0 framing error
                        if_z    mov         phsb, _rxWait0                          'Timeout 1 - phsb used as scratch since ctrb should be off
                        if_z    sub         phsb, _rxWait1                          'Timeout 2 - see page 98 for timeout notes
                        if_z    cmp         phsb, timeout                   wc      'Timeout 3 - c=0 reset, c=1 no reset
                        if_z    mov         _rxPrevByte, _rxByte                    'Handoff
                        if_z    jmp         #rxBit0

                    { fall through to recovery mode for framing errors }

{ Parsing Instructions
  There are four parsing instructions per received byte, labelled A-D. These instructions are shifted
    into the receive loop at rxShiftedA-D. Each group must take four registers with no gaps between
    them (use nops if necessary).
  rxFirstParsingGroup identifies the first parsing group to be executed on parser reset.
  Parsing groups are identified by the byte being received when they execute.
  Instructions A and B are executed consecutively during the interval after bit[6] has been sampled, but
    before bit[7] is sampled. Instructions C and D are executed consecutively after bit[7], but before
    the stop bit. (This arrangement was found most conducive for parsing a Crow header.)
  _rxOffset determines the parsing group to be executed for the next byte. It is automatically set to
    four before instruction A, which means the default is to execute the following parsing group
    during the next byte. Parsing code can change _rxOffset to change the next group (it is a signed
    value, and should always be a multiple of four).
  The Flag_WriteByte bit of _rxFlags determines whether the current byte will be written to the hub (this
    actually occurs when the next byte is received). This flag is automatically cleared on parser
    reset, and it must be manually set or cleared after that.
  If Flag_WriteByte is set then the byte will be written to ++_rxAddr -- i.e. _rxAddr is automatically
    incremented BEFORE writing the byte (_rxAddr is not changed unless the byte is written). This means
    _rxAddr must initially be set to the desired address minus one. _rxAddr is undefined on parser reset.
  Before instruction A, _rxCountdown is decremented and the z flag indicates whether the countdown is
    zero. _rxCountdown is undefined on parser reset.
  Before instruction A the c flag is set to bit[6]. Before instruction C the c flag is set to bit[7].
  Parsing code may change the flags (but remember c will be set to bit[7] between B and C).
  Parsing code MUST NOT change the value of _rxByte. Doing so will cause the checksums to be bad.
  The F16 checksums are automatically calculated in the receive loop, but checking their validity
    must be done by the parsing code. This must be done in the parsing group immediately after F16 C1 is
    received (which will always be a payload byte, except for the very last checkbyte of the packet,
    which is verified in ReceiveCommandFinish). Immediately after F16 C1 is received and processed
    both running checksums (_rxF16U and _rxF16L) should be zero.
  Summary:
    On parser reset:
      (parsing group rxFirstParsingGroup is selected for the first byte)
      _rxFlags[Flags_WriteByte] := 0    (don't write to hub)
      _rxF16U := _rxF16L := 0           (F16 checksums are reset, as per Crow specification)
      _rxCountdown = <undefined>        (so z will be undefined at rxFirstParsingGroup instruction A) 
      _rxPrevByte = <undefined>
      _rxAddr = <undefined>
    Before A and B:
      _rxPrevByte is the byte received before this one (upper bytes are zero); it may be changed
      _rxByte (READ-ONLY) is complete to bit[6], but bit[7] is undefined (upper bytes are zero)
      _rxF16U and _rxF16L (READ-ONLY) are calculated up to the previous byte
      _rxCountdown := _rxCountdown - 1
      z := _rxCountdown==0
      c := bit[6]
    Before C and D:
      (z is not changed, so it maintains whatever value it had after B)
      c := bit[7]
      _rxByte (READ-ONLY) is complete (upper bytes are zero)
}
rxFirstParsingGroup
rxH0








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
  The partial sending routines exist to allow user code to send payload bytes from multiple random
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
txPerformChecks                 test        flags, #Flag_Mute           wc
                        if_c    jmp         SendHeader_ret
                                max         payloadSize, maxPayloadSize

                                { compose header bytes RH0-RH1; RH2 (token) is already set }
                                mov         par, payloadSize                    'shadow PAR used to compose first byte of header
                                shr         par, #8                             '(assumes payloadLength <= 2047)
txApplyTemplate                 or          par, #0-0
                                mov         _txAddr, hubScratch                      
                                wrbyte      par, _txAddr
                                add         _txAddr, #1
                                wrbyte      payloadSize, _txAddr

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

                                { retain line }
txRetainLine                    or          dira, txMask

                                { send RH0-RH2 }
                                mov         _txAddr, hubScratch
                                mov         _txCount, #3
                                call        #txSendBytes

                                { send RH3-RH4 (the header F16) }
                                call        #txSendAndResetF16

                                { prepare for sending payload bytes }
                                andn        flags, #Flag_SendCheck              'the SendCheck flag is set when payload bytes are sent
                                mov         _txMaxChunkRemaining, #128          'the maximum number of bytes for a full chunk (the last may be partial)
SendHeader_ret
SendFinalHeader_ret
SendIntermediateHeader_ret      ret
    

{ SendPayloadBytes (Partial Sending Routine)
  This routine sends payload bytes for an response packet that has been started with a
    call to SendFinalHeader or SendIntermediateHeader.
  Note that the total number of bytes
    to send must still be known before sending the header. The total sum of bytes sent using
    one or more SendPayloadBytes calls must exactly match the payloadSize passed to the header
    sending routine -- if it does not, then the Crow host (i.e. PC) will experience some sort
    of error (e.g. timeout, unexpected number of bytes, bad checksum).
  Usage:
            mov     payloadSize, <number of bytes to send with this call, may be zero>
            mov     payloadAddr, <base address of bytes to send>
            call    #SendPayloadBytes
  After this call payloadSize will be zero and payloadAddr will point to the address after
    the last byte sent.
}
SendPayloadBytes
                                test        flags, #Flag_Mute               wc  'skip if responses muted
                        if_c    jmp         SendPayloadBytes_ret
:loop
                                mov         _txCount, payloadSize           wz
                        if_z    jmp         SendPayloadBytes_ret                'exit: nothing to send
                                max         _txCount, _txMaxChunkRemaining
                                sub         payloadSize, _txCount
                                sub         _txMaxChunkRemaining, _txCount  wz  'z=0 implies txCount < _txMaxChunkRemaining, and also that
                                                                                ' payloadSize is now zero -- in other words, this is the last bit of payload data
                                                                                ' to send with this call, but the chunk is not full
                                mov         _txAddr, payloadAddr

                                call        #txSendBytes
                                or          flags, #Flag_SendCheck              'if any payload bytes have been sent then a checksum must follow eventually

                                mov         payloadAddr, _txAddr

                        if_nz   jmp         SendPayloadBytes_ret                'exit: chunk is not finished, but all bytes for this call have been sent 

                                { chunk is finished, but there may be more payload bytes to send, so send checksum now }

                                call        #txSendAndResetF16

                                { prep for next chunk }
                                andn        flags, #Flag_SendCheck
                                mov         _txMaxChunkRemaining, #128
 
                                jmp         #:loop 

SendPayloadBytes_ret            ret


{ FinishSending (Partial Sending Routine)
  This routine finishes the response packet.
  This routine MUST be called after a call to SendFinalHeader or SendIntermediateHeader,
    even if there are no payload bytes.
}
FinishSending
                                test        flags, #Flag_Mute               wc      'skip if responses muted
                        if_c    jmp         FinishSending_ret
                                test        flags, #Flag_SendCheck          wc      'send final payload checksum if necessary
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
txPerformChecks2                 test        flags, #Flag_Mute        wc  'c=1 muted
                        if_c    jmp         Send_ret
                                max         payloadSize, maxPayloadSize

                                { compose header bytes RH0-RH1; RH2 (token) is already set }
                                mov         par, payloadSize                    'shadow PAR used to compose first byte of header
                                shr         par, #8                             '(assumes payloadLength <= 2047)
txApplyTemplate2                 or          par, #0-0
                                mov         _txAddr, hubScratch                      
                                wrbyte      par, _txAddr
                                add         _txAddr, #1
                                wrbyte      payloadSize, _txAddr

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

                                { retain line }
                    or          dira, txMask

                                { send RH0-RH2 }
                                mov         _txAddr, hubScratch
                                mov         _txCount, #3
                                call        #txSendBytes

                                { send RH3-RH4 (the header F16) }
                                call        #txSendAndResetF16

                                { send packet body (chunks of payload bytes with checksums) }
txPayloadLoop                   mov         _txCount, payloadSize           wz
                        if_z    jmp         #txLoopExit
                                max         _txCount, #128                      'next chunk size (max of 128 bytes)
                                sub         payloadSize, _txCount
                                mov         _txAddr, payloadAddr
                                call        #txSendBytes
                                mov         payloadAddr, _txAddr                'preserve payload address for next chunk
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
                                mov         _txAddr, hubScratch
                                wrbyte      _txF16U, _txAddr
                                add         _txAddr, #1
                                mov         _txCount, #2                        'sending prep
                                wrbyte      _txF16L, _txAddr
                            
                                { send F16 }
                                mov         _txAddr, hubScratch
                                call        #txSendBytes

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

txSendAndResetF16_ret           ret




bitPeriod           long    32
txMask              long    |< 30
stopBitDuration     long    32
maxPayloadSize      long    2047
hubScratch          long    20000

flags               long    0

payloadSize     res
payloadAddr     res

_tmp            res

_txMaxChunkRemaining    res

_txAddr         res
_txCount        res

_txNextByte     res
_txByte         res
_txF16L         res
_txF16U         res


