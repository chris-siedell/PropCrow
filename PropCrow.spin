
con
    _clkmode = xtal1 + pll16x
    _xinfreq = 5_000_000

    conMuteFlag     = %0100_0000


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
                                mov         payloadSize, #40
                                call        #SendFinalAndReturn

                                mov         cnt, cnt
                                add         cnt, pause
                                waitcnt     cnt, #0
                                jmp         #mainLoop

addr                long    60000 
pause               long    4_000_000



                                





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





{ Sending Routines 
  This routine requires that the entire payload be in a contiguous block of hub ram.
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
                                movs        txApplyTemplate, #$90
                                jmp         #txPerformChecks
SendIntermediate
                                movs        txApplyTemplate, #$80

                                { checks: ensure not muted, and ensure payload size is within buffer size }
txPerformChecks                 test        packetInfo, #conMuteFlag        wc  'c=1 muted
                        if_c    jmp         Send_ret
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
txReleaseLine                   andn        dira, txMask
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
                                wrbyte      _txF16L, _txAddr
                            
                                { send F16 }
                                mov         _txAddr, hubScratch
                                mov         _txCount, #2
                                call        #txSendBytes

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

txSendAndResetF16_ret           ret




bitPeriod           long    32
txMask              long    |< 30
stopBitDuration     long    34
maxPayloadSize      long    2047
hubScratch          long    20000

packetInfo          long    0

payloadSize     res
payloadAddr     res

_tmp            res

_txAddr         res
_txCount        res

_txNextByte     res
_txByte         res
_txF16L         res
_txF16U         res


