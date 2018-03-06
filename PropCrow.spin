
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


