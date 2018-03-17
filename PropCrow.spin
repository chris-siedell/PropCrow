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


{ Buffer Size Settings
  These cMax* settings determine the sizes of the reserved buffers.
  By specification, Crow command payloads may not exceed 2047 bytes (MaxRxPayloadSize).
}
cMaxRxPayloadSize   = 300   'may be 2-2047 (lower limit due to mechanism to avoid buffer overruns)
cMaxTxPayloadSize   = 100   'may be 0-2047
cMaxUserPorts       = 10    'any two byte value (as memory allows)

cMaxNumPages        = 10

cRxBufferLongs   = (cMaxRxPayloadSize/4) + 1
cTxBufferLongs   = (cMaxTxPayloadSize/4) + 1
cUserPortsLongs  = ((cMaxUserPorts*6) / 4) + 1

{ flags and masks }
CommandTypeFlag     = %0001_0000    'for CH0
cAddressMask         = %0001_1111    'for CH3
cMuteFlag            = %0100_0000    'for CH3

{ masks used for the serialOptions bitfields }
cUseSource          = %0000_0001
cUseBaudDetect      = %0000_0010
cUseContRecal       = %0000_0100
cUseTwoStopBits     = %1000_0000

{ masks used for otherOptions bitfield }
cEnableReset        = %0000_0001
cAllowRemoteChanges = %0000_0010
cSendCrowErrors     = %0000_0100

{ other }
cPropCrowID         = $abcd 'must be two byte value


{ paging constants }
cPage           = 385
cPageMaxSize    = 72
cPageLimit      = cPage + cPageMaxSize


{ Crow error codes; values from v2 specification }
cExcPayloadSize         = 0     'The command payload exceeds device's capacity.
cPortNotOpen            = 1     'The port is not open.
cCorruptPayloadF16      = 2     'The command payload is corrupt. One or more Fletcher16 checksums is incorrect.
cImplementationError    = 3     'An implementation specific error has occurred.

{ implementation error codes; must not conflict with Crow error codes }
cPageOOB        = 20    'Page index is out-of-bounds.
cEmptyPage      = 21    'Page size is zero.
cExcPageSize    = 22    'Page size exceeds space.
cBadPageSig     = 23    'Incorrect page signature.
cRunawayPage    = 24    'Execution reached end of page.

{   The cSendChecksums flag indicates whether the F16 checksums for the last payload chunk still need to be sent. It is used
  in FinishSending. Bit 9 is used because the flag is stored in outb, i.e. header byte CH3, which means bit 9 will be cleared
  by default, saving an instruction.
}
cSendChecksums  = %1_0000_0000

{ page indices }
cCalculateTimings   = 0
cGetDeviceInfo      = 1
cUserCommand        = 2
cPropCrowAdmin      = 3
cReportCrowError    = 4
cNumPages           = 5     'cNumPages must be 9-bit value <= cInvalidPage
cInvalidPage        = 511   'signifies no valid page loaded

obj
    peekpoke : "PeekPoke"


var

    long    __userPorts[cUserPortsLongs]
    long    __rxBuffer[cRxBufferLongs]
    long    __txBuffer[cTxBufferLongs]


pub new

    dira[26] := 1
    outa[26] := 1

    peekpoke.setParams(31, 30, 115200, 2)
    peekpoke.new

    word[30000] := @PageTable
    word[30002] := @Entry
    word[30004] := @ControlBlock
 
    word[@PageTable][0] := @CalculateTimings
    word[@PageTable][2] := @GetDeviceInfo
    word[@PageTable][4] := @UserCommand
    word[@PageTable][6] := @PropCrowAdmin
    word[@PageTable][8] := @ReportCrowError


    __numUserPorts      := 3
    __userPorts.word[0] := 0
    __userPorts.word[3] := 1
    __userPorts.word[6] := 78

    __userPortsAddr     := @__userPorts
    __rxBufferAddr      := @__rxBuffer
    __txBufferAddr      := @__txBuffer
    __datConstansAddr   := @DatConstants
    __pageTableAddr     := @PageTable

    __objBaseAddr       := @@0

    cognew(@Entry, @ControlBlock)

    repeat
        result += 1

dat

{ PageTable
   
    Format:
      pos  len  value
      0    2    address of page
      2    1    (not used)
      3    1    length of page
}    

PageTable

'0: CalculateTimings
word    0
byte    0
byte    CalculateTimings_end - CalculateTimings + 1

'1: GetDeviceInfo
word    0
byte    0
byte    GetDeviceInfo_end - GetDeviceInfo + 1

'2: UserCommand
word    0
byte    0
byte    UserCommand_end - UserCommand + 1

'3: PropCrowAdmin
word    0
byte    0
byte    PropCrowAdmin_end - PropCrowAdmin + 1

'4: ReportCrowError
word    0
byte    0
byte    ReportCrowError_end - ReportCrowError + 1





  
{ ControlBlock

    The control block stores both initialization and runtime settings to control an instance
  of PropCrow. It's address is passed to the instance via par.

    The block must be long-aligned.

    Format:
      pos  len  type value
      0    4    s    activeBaudrate
      4    2    s    activeInterbyteTimeout, in milliseconds
      6    2    s    activeBreakThreshold, in milliseconds
      8    4    s    activeSerialOptions, bitfield
      12   4    s    resetBaudrate
      16   2    s    resetInterbyteTimeout, in milliseconds
      18   2    s    resetBreakThreshold, in milliseconds
      20   4    s    resetSerialOptions, bitfield
      24   1    s    activeSerialSettingsChanged, flag (other cogs set to non-zero, PropCrow sets to zero)
      25   1    s    otherOptions, bitfield
      26   2    s    numUserPorts
      28   2    I    maxUserPorts
      30   2    I    userPortsAddr
      32   1    I    rxPin
      33   1    I    txPin
      34   2    I    rxBufferAddr
      36   2    I    txBufferAddr
      38   2    I    maxRxPayloadSize
      40   2    I    maxTxPayloadSize
      42   2    I    datConstantsAddr
      44   2    I    pageTableAddr
      46   1    I    numPages
      47   1    I    crowAddress
      48   1    I    accessLockID, values 8-255 => lock is disabled
      49   1    D    cogID
      50   2    D    objBaseAddr
      52   4    -    txScratch, used for composing response headers
     (56)

    The first four items (baudrate through options bitfield) are the active serial settings used by
  the implementation when it starts up. The second set of serial settings are those used when the
  implementation receives a reset command (either a break condition or an explicit command). On reset,
  the reset settings are copied to the active settings.
  
    If another cog changes any of the active serial settings after launch it will need to raise the
  active serial settings changed flag by setting it to a non-zero value (all under shared access lock).
  The PropCrow implementation will clear the flag when it incorporates the changes. The implementation
  will not load the settings from the hub unless it experiences framing or parsing errors, or it is
  commanded to do so by the host. Framing errors can by induced by other cogs by making the rx pin a
  brief low output, but make sure the other hardware (i.e. the host's UART) can tolerate this.

    Types:
      s: shared setting, all cogs must use lock to read and write (if access lock is enabled)
      I: initialization constant, must be set before cog launches, and remain constant thereafter
      D: diagnostic, set by PropCrow cog only

    The access lock allows other cogs to change settings in a safe way. If settings never change then
  the access lock may be disabled. (Values of 0-7 enable the lock, anything else disables it.)

    PropCrow assumes hub[0:4] is the clock frequency, and hub[4] is the clock mode. It considers
  these settings to be protected by the access lock. 
}

ControlBlock
                    long    115200              'activeBaudrate
                    word    250                 'activeInterbyteTimeout, in milliseconds
                    word    100                 'activeBreakThreshold, in milliseconds
                    long    $0707_0101          'activeSerialOptions
                    long    115200              'resetBaudrate
                    word    250                 'resetInterbyteTimeout, in milliseconds
                    word    100                 'resetBreakThreshold, in milliseconds
                    long    $0707_0101          'resetSerialOptions
                    byte    0                   'activeSerialSettingsChanged
                    byte    1                   'otherOptions
__numUserPorts      word    0                   'numUserPorts
                    word    cMaxUserPorts       'maxUserPorts
__userPortsAddr     word    0-0                 'userPortsAddr
                    byte    31                  'rxPin
                    byte    30                  'txPin
__rxBufferAddr      word    0-0                 'rxBufferAddr
__txBufferAddr      word    0-0                 'txBufferAddr
                    word    cMaxRxPayloadSize   'maxRxPayloadSize
                    word    cMaxTxPayloadSize   'maxTxPayloadSize
__datConstansAddr   word    0-0                 'datConstantsAddr
__pageTableAddr     word    0-0                 'pageTableAddr
                    byte    cNumPages           'numPages
                    byte    1                   'crowAddress
                    byte    255                 'accessLockID
                    byte    0-0                 'cogID
__objBaseAddr       word    0-0                 'objBaseAddr
                    long    0                   'txScratch



{ UserPortsTable

    Each entry in this table defines a port opened by user code, and specifies what code to invoke
  to process data received on that port.

    The table must be word-aligned.

    Entry format:
      pos  len  value
      0    2    port number
      2    1    user code type (0: uses port control block; 1-127: uses code page with this length)
      3    1    <not used>
      4    2    address (either of port control block, or of code page)

    Rules:
      - access lock (if enabled) must be used to read and write
      - valid entries start at index 0
      - no gaps
      - sorted by ascending port number
      - all port numbers unique (can't be opened twice)
      - values at index numUserPorts and above are undefined
      - numUserPorts in [0, maxNumUserPorts)
}



DatConstants

{ This data is the same for all instances of PropCrow. It is kept separate from the
  control block to make it easier to modify PropCrow to allow multiple instances. }

{ DeviceInfoTemplate (@DatConstants + 0)
  A template for sending getDeviceInfo responses. The mutable parts (for user ports) are
  sent separately.
}
long    $0000_0100 | ((cPropCrowID & $ff) << 24) | ((cPropCrowID & $ff00) << 8)             'Crow v1, implementationID = cPropCrowID
long    $0003_0000 | ((cMaxRxPayloadSize & $ff) << 8) | ((cMaxRxPayloadSize & $700) >> 8)   'max commmand payload size, 3 admin ports (upper byte not sent) 
long    $0100_0000                                                                          'admin ports 0 and 1
long    $0000_0000 | ((cPropCrowID & $ff) << 8) | ((cPropCrowID & $ff00) >> 8)              'admin port cPropCrowID (upper word not sent)

{ NibbleTable (@DatConstants + 16)
  A table of low bit counts for integers 0 to 15. Used for continuous recalibration.
}
byte 4, 3, 3, 2, 3, 2, 2, 1, 3, 2, 2, 1, 2, 1, 1, 0

{ Strings
}
ImpErrorMessageStart    byte    "PropCrow error: ", 0

dat


org cPage
ReportCrowError
                                jmp         #ReceiveCommand
ReportCrowError_end             jmp         #RunawayPageHandler
fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.


org cPage
UserCommand
                                'echo the port
                                mov         _x, dirb
                                wrword      _x, txBufferAddr
                                mov         payloadSize, #2
                                mov         payloadAddr, txBufferAddr

                                jmp         #SendFinalResponse

UserCommand_end                 jmp         #RunawayPageHandler
fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.


org cPage
PropCrowAdmin
                                mov         payloadAddr, #0
                                mov         payloadSize, #8
                                jmp         #SendFinalResponse
PropCrowAdmin_end               jmp         #RunawayPageHandler
fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.


org cPage
GetDeviceInfo
                                call        #LockSharedAccess

                                rdword      _x, numUserPortsAddr                    '_x = num open user ports to report
                                max         _x, #255                                'getDeviceInfo limited to reporting 255 user ports

                                mov         payloadSize, _x                         'response payload size is 14 + 2*<num user ports> (assumes 3 admin protocols)
                                shl         payloadSize, #1
                                add         payloadSize, #14
                                call        #SendFinalHeader

                                mov         payloadAddr, deviceInfoAddr
                                mov         payloadSize, #7
                                call        #SendPayloadBytes                       'send up to num reported user ports

                                wrbyte      _x, txBufferAddr
                                mov         payloadAddr, txBufferAddr
                                mov         payloadSize, #1
                                call        #SendPayloadBytes                       'send number of reported user ports

                                mov         payloadAddr, deviceInfoAddr
                                add         payloadAddr, #8
                                mov         payloadSize, #6
                                call        #SendPayloadBytes                       'send open admin ports from template

                                cmp         _x, #0                   wz
                        if_z    jmp         #:finish                                '...skip if no user ports

                                mov         payloadAddr, userPortsAddr              'send the user port numbers directly from the table
                                sub         payloadAddr, #5

:loop                           add         payloadAddr, #6                         'MSB             
                                mov         payloadSize, #1
                                call        #SendPayloadBytes
                                sub         payloadAddr, #2                         'LSB
                                mov         payloadSize, #1
                                call        #SendPayloadBytes

                                djnz        _x, #:loop       

:finish                         call        #FinishSending
 
                                call        #UnlockSharedAccess
                                
                                jmp         #ReceiveCommand

GetDeviceInfo_end               jmp         #RunawayPageHandler

fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.



org cPage

{ CalculateTimings
  This routine calculates the serial timings (in clocks) based on the settings stored in the hub.
}
CalculateTimings
                                call        #LockSharedAccess

                                mov         _addr, par
                                rdlong      _calcBaud, _addr
                                add         _addr, #4
                                rdword      _calcIBTimeout, _addr
                                add         _addr, #2
                                rdword      _calcBreak, _addr
                                add         _addr, #2
                                rdlong      _calcOptions, _addr
                                rdlong      _calcClk, #0

                                call        #UnlockSharedAccess
                            
                                mov         _x, _calcClk                    
                                shl         _x, #1
                                mov         _y, _calcBaud
                                call        #Divide
                                mov         _calcTwoBit, _y

                                mov         bitPeriod0, _calcTwoBit
                                shr         bitPeriod0, #1
                                min         bitPeriod0, #34                         'bitPeriod0 ready
                            
                                mov         bitPeriod1, bitPeriod0
                                test        _calcTwoBit, #1                     wc
                        if_c    add         bitPeriod1, #1                          'bitPeriod1 ready

                                mov         rxBitPeriod5, bitPeriod0
                                min         rxBitPeriod5, #33

                                mov         startBitWait, bitPeriod0
                                shr         startBitWait, #1
                                sub         startBitWait, #10                       'startBitWait ready; must not be < 5 (won't if bitPeriod0 >= 34)
            
                                mov         _x, _calcClk
                                mov         _y, #10
                                call        #Multiply
                                mov         _y, _calcBaud
                                call        #Divide
                                mov         stopBitDuration, _y
                                mov         _x, bitPeriod0
                                mov         _y, #5
                                call        #Multiply
                                sub         stopBitDuration, _x
                                mov         _x, bitPeriod1
                                shl         _x, #2
                                sub         stopBitDuration, _x
                                test        _calcOptions, #cUseTwoStopBits      wc
                        if_c    add         stopBitDuration, bitPeriod1             'stopBitDuration ready                                

                                mov         _x, _calcClk
                                mov         _y, k1000
                                call        #Divide
                                mov         _calcClk, _y                                '_clk is now clocks per millisecond

                                mov         _x, _calcIBTimeout
                                call        #Multiply
                                mov         ibTimeout, _x                           'ibTimeout ready

                                mov         recoveryTime, _calcTwoBit
                                shl         recoveryTime, #3                        'recoveryTime ready

                                mov         _x, _calcClk
                                mov         _y, _calcBreak
                                call        #Multiply
                                mov         _y, recoveryTime
                                call        #Divide
                                min         _y, #1
                                mov         breakMultiple, _y                       'breakMultiple ready

                                mov         rxPhsbReset, #19
                                add         rxPhsbReset, startBitWait
                                add         rxPhsbReset, bitPeriod0                 'rxPhsbReset ready (= 5 + startBitWait + bitPeriod0 + 5 + 4 + 4 + 1)

                                jmp         #RecoveryMode

k1000                           long    1000

CalculateTimings_end            jmp         #RunawayPageHandler

fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.

dat 
org 0

Entry

{ The first 16 cog registers will contain a lookup table after initialization. At launch, it
  contains initialization code. par = address of control block. }
                                
                                mov         _addr, par

                                add         _addr, #24                          'serSettingsChangedAddr
                                mov         serSettingsChangedAddr, _addr
                
                                add         _addr, #2                           'numUserPortsAddr
                                mov         numUserPortsAddr, _addr

                                add         _addr, #2                           'maxUserPorts
                                rdword      maxUserPorts, _addr
                                
                                add         _addr, #2                           'userPortsAddr
                                rdword      userPortsAddr, _addr

                                add         _addr, #2                           'rxPin, ctrb setup
                                rdbyte      _x, _addr
                                shl         rxMask, _x
                                movs        lowCounterMode, _x
                                mov         ctrb, lowCounterMode
                                mov         frqb, #1              

                                jmp         #FinishInit


long 0[16-$]
fit 16
org 16

{ RunawayPageHandler
    Every valid page must end with an unconditional jmp to this handler (i.e. "jmp #16"). It is placed
  here since this position should remain constant in future revisions (for precompiled code pages).
}
RunawayPageHandler
                                mov         _error, #cRunawayPage
                                jmp         #ImplementationErrorHandler

{ Multiply
    Algorithm from the Spin interpreter, with sign code removed. It is placed here for the benefit of
  code pages (its position shouldn't change).
    Before: _x = multiplier
            _y = multiplicand
    After: _x = lower half of product
           _z = upper half of product
}
Multiply
                                mov         _z, #0
                                mov         inb, #32
                                shr         _x, #1              wc
:mmul                   if_c    add         _z, _y              wc
                                rcr         _z, #1              wc
                                rcr         _x, #1              wc
                                djnz        inb, #:mmul
Multiply_ret                    ret


{ Divide 
    Algorithm from the Spin interpreter, with sign code removed. It is placed here for the benefit of
  code pages (its position shouldn't change).
    Before: _x = dividend
            _y = divisor
    After: _x = remainder
           _y = quotient
}
Divide
                                mov         _z, #0
                                mov         inb, #32
:mdiv                           shr         _y, #1              wc, wz
                                rcr         _z, #1
                        if_nz   djnz        inb, #:mdiv
:mdiv2                          cmpsub      _x, _z              wc
                                rcl         _y, #1 
                                shr         _z, #1
                                djnz        inb, #:mdiv2
Divide_ret                      ret




{ Special/Shadow Register Usage

    PropCrow sets up ctrb as a continuously running NEG counter on rx pin with frqb=1. This should not be changed.

    PropCrow does not touch the counter A registers (frqa, ctra, phsa) or the video registers (vcfg, vscl).

    par points to the control block.

    PropCrow does use shadow and reserved registers. Specifically:

    Locally to ReceiveCommand, shifted parsing code, and FinishReceiveCommand:
      sh-ina = CH0, to save T flag
      sh-inb = local scratch
      sh-cnt = rxF16U

    Globally:
      sh-par = token    'must remain unchanged until final header has been sent
      dirb   = port     'must remain unchanged until code has finished with port number
      outb   = CH3      'must remain unchanged until all bytes have been sent, bit 9 used for cSendChecksums flag

}


                                
{ ReceiveCommand
  This routine contains the receive loop used to receive and process bytes. Processing is done using
    shifted parsing instructions, which are explained in more detail in the "Parsing Instructions" 
    section below.
}
ReceiveCommand
                            xor     outa, pin27

                                { pre-loop initialization }
                                mov         rxStartWait, rxContinue
                                movs        rxMovA, #rxFirstParsingGroup
                                movs        rxMovB, #rxFirstParsingGroup+1
                                movs        rxMovC, #rxFirstParsingGroup+2
                                movs        rxMovD, #rxFirstParsingGroup+3
                                mov         _rxResetOffset, #0
                                mov         _rxWait0, startBitWait
                                mov         _rxMixed, rxMixedInitReset

                                test        rxMask, ina                     wz      'z=1 => rx pin already low -- missed falling edge

                        if_nz   waitpne     rxMask, rxMask                          'wait for start bit edge
                        if_nz   add         _rxWait0, cnt
                        if_nz   waitcnt     _rxWait0, bitPeriod0                    'wait to sample start bit (for initial byte only)
                        if_nz   test        rxMask, ina                     wc      'c=1 framing error; c=0 continue, with parser reset
                        if_z    jmp         #RecoveryMode                           '...exit for missed falling edge (need edge for cont-recal)
                        if_c    jmp         #FramingError

                                { the receive loop -- c=0 reset parser}

'bit0 - 34 clocks
rxBit0                          waitcnt     _rxWait0, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_0001
                        if_nc   mov         phsb, rxPhsbReset                       'Cont-Recal 1 - reset low clocks count on reset; MUST change rxPhsbReset calculation if moved
                                mov         _rxLastWait1, _rxWait1                  'Cont-Recal 2 - save _rxWait1 for last byte; must come before wait transfer
                                mov         _rxWait1, _rxWait0                      'Wait 2 - transfer
                                mov         _rxWait0, startBitWait                  'Wait 3
                        if_nc   mov         _rxF16L, #0                             'F16 1 - zero checksums on reset; see page 90

'bit1 - 34 clocks
rxBit1                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_0010
                        if_nc   mov         cnt, #0                                 'F16 2 - sh-cnt is rxF16U
                        if_c    add         _rxF16L, _rxPrevByte                    'F16 3 - this if_c is not optional
                        if_c    cmpsub      _rxF16L, #255                           'F16 4 - the if_c's are optional from this point on for F16
                        if_c    add         cnt, _rxF16L                            'F16 5
                        if_c    cmpsub      cnt, #255                               'F16 6

'bit 2 - 34 clocks
rxBit2                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_0100
                        if_nc   mov         _rxOffset, _rxResetOffset               'Shift 1 - go back to first parsing group on reset (see page 93)
                                subs        _rxResetOffset, _rxOffset               'Shift 2 - adjust reset offset
                                adds        rxMovA, _rxOffset                       'Shift 3 - (next four) offset addresses for next parsing group
                                adds        rxMovB, _rxOffset                       'Shift 4
                                adds        rxMovC, _rxOffset                       'Shift 5

'bit 3 - 34 clocks
rxBit3                          waitcnt     _rxWait1, bitPeriod0
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_1000
                                adds        rxMovD, _rxOffset                       'Shift 6
                                mov         _rxOffset, #4                           'Shift 7 - restore default offset (must be done before shifted instructions)
rxMovA                          mov         rxShiftedA, 0-0                         'Shift 8 - (next four) shift parsing instructions into place
rxMovB                          mov         rxShiftedB, 0-0                         'Shift 9
rxMovC                          mov         rxShiftedC, 0-0                         'Shift 10

'bit 4 - 34 clocks
rxBit4                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0001_0000
rxMovD                          mov         rxShiftedD, 0-0                         'Shift 11
                                movs        rxAddLowerNibble, rxByte                'Cont-Recal 3 - determine low bit count of lower nibble; must follow mux of bit 3
                                andn        rxAddLowerNibble, #%1_1111_0000         'Cont-Recal 4 - (spacer required)
                                test        _rxMixed, writeByteFlag         wc      'Write 1 - c=1 write byte to hub
                        if_c    add         _rxAddr, #1                             'Write 2 - increment address (pre-increment saves re-testing the flag)

'bit 5 - 33 clocks
rxBit5                          waitcnt     _rxWait1, rxBitPeriod5
                                testn       rxMask, ina                     wz
                        if_c    wrbyte      _rxPrevByte, _rxAddr                    'Write 3 - wrbyte excludes any other instructions besides testn

'bit 6 - 34 clocks
rxBit6                          waitcnt     _rxWait1, bitPeriod1
                                test        rxMask, ina                     wc
                                muxz        rxByte, #%0010_0000
                                muxc        rxByte, #%0100_0000
rxAddLowerNibble                add         _rxMixed, 0-0                           'Cont-Recal 5 - add count of low data bits of current byte's lower nibble
                                sub         _rxCountdown, #1                wz      'Countdown - used by parsing code to determine when F16 follows payload bytes
rxShiftedA                      long    0-0                                         'Shift 12 - (next four) execute shifted instructions
rxShiftedB                      long    0-0                                         'Shift 13

'bit 7 - 34 clocks
rxBit7                          waitcnt     _rxWait1, bitPeriod0
                                test        rxMask, ina                     wc
                                muxc        rxByte, #%1000_0000
rxShiftedC                      long    0-0                                         'Shift 14
rxShiftedD                      long    0-0                                         'Shift 15
                                mov         _rxPrevByte, rxByte                     'Handoff
                                shr         rxByte, #4                              'Cont-Recal 6 - start getting low bits count for upper nibble
                                movs        rxAddUpperNibble, rxByte                'Cont-Recal 7 - (spacer required)

rxStopBit                       waitcnt     _rxWait1, bitPeriod0                    'see page 98
                                testn       rxMask, ina                     wz      'z=0 framing error

rxStartWait                     long    0-0                                         'wait for start bit, or exit loop

                        if_z    add         _rxWait0, cnt                           'Wait 1

'start bit - 34 clocks
rxStartBit              if_z    waitcnt     _rxWait0, bitPeriod0
                        if_z    test        rxMask, ina                     wz      'z=0 framing error
rxAddUpperNibble        if_z    add         _rxMixed, 0-0                           'Cont-Recal 8 - finish adding low bit count for upper nibble of previous byte
                        if_z    mov         inb, _rxWait0                           'Timeout 1 - using sh-inb as scratch
                        if_z    sub         inb, _rxWait1                           'Timeout 2 - see page 98 for timeout notes
                        if_z    cmp         inb, ibTimeout                 wc       'Timeout 3 - c=0 reset, c=1 no reset
                if_z_and_nc     mov         _rxMixed, rxMixedTimoutReset            'Mixed - reset due to timeout (takes djnz into account); see "_rxMixed Notes"
                        if_z    djnz        _rxMixed, #rxBit0                       'Mixed - add to byteCount (negative); also finishes reset of _rxMixed on timeout
                    
                        { fall through for framing errors }

FramingError
                                { todo: add logic }
                                jmp         #RecoveryMode


ParsingError
                        
                        { fall through to recovery mode }

{ RecoveryMode
  When framing or parsing errors occur the implementation enters recovery mode. In this mode the implementation
    waits for the rx line to be in high-idle for a certain period of time before attempting to receive another
    command. If the line is low for long enough then the implementation determines that a break condition has occurred.
  See page 99.
}
'todo (3/17): does the removal of the ctrb off code change any timings?
RecoveryMode
                                mov         cnt, recoveryTime
                                add         cnt, cnt
                                mov         _rcvyPrevPhsb, phsb                     'first interval always recoveryTime+1 counts, so at least one loop for break 
                                mov         inb, breakMultiple                      'sh-inb is countdown to break detection
rcvyLoop                        waitcnt     cnt, recoveryTime
                                mov         _rcvyCurrPhsb, phsb
                                cmp         _rcvyPrevPhsb, _rcvyCurrPhsb    wz      'z=1 line always high, so exit
                        if_z    jmp         #ReceiveCommand                         '...exit: line is idle -- ready for next command
                                mov         par, _rcvyPrevPhsb
                                add         par, recoveryTime
                                cmp         par, _rcvyCurrPhsb              wz      'z=0 line high at some point
                        if_nz   mov         inb, breakMultiple                      'reset break detection countdown
                                mov         _rcvyPrevPhsb, _rcvyCurrPhsb
                                djnz        inb, #rcvyLoop

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
  The writeByteFlag of _rxMixed determines whether the current byte will be written to the hub.
    This flag is automatically cleared on parser reset, and it must be manually set or cleared after that.
  If writeByteFlag is set then the byte will be written to ++_rxAddr. Note that _rxAddr is automatically
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
  The parsing code must ensure that the payload buffer is not exceeded. The excPayloadFlag is used
    for that purpose (it is cleared on reset).
  Summary:
    On parser reset:
      parsing group rxFirstParsingGroup is selected
      _rxMixed is reset                 (byteCount and lowBitCount are reset, writeByteFlag and excPayloadFlag are cleared)
      _rxF16U (sh-inb) := _rxF16L := 0  (F16 checksums are reset, as per Crow specification)
      _rxCountdown = <undefined>        (so z will be undefined at rxFirstParsingGroup instruction A) 
      rxPrevByte = <undefined>
      _rxAddr = <undefined>
    Before A and B:
      _rxByte (READ-ONLY) is complete to bit[6], but bit[7] is from previous byte (upper bytes are zero)
      _rxPrevByte (READ-ONLY) is the byte received before this one (upper bytes are zero)
      (the F16 checksums are not yet ready for testing)
      _rxCountdown := _rxCountdown - 1
      _rxOffset := 4                    (this is a signed value, and it determines the next group executed)
      z := _rxCountdown==0
      c := bit[6]
    Before C and D:
      _rxByte (READ-ONLY) is complete (upper bytes are zero)
      _rxPrevByte (READ-ONLY) has been shifted down by 4 bits
      _rxF16U (sh-inb) and _rxF16L (READ-ONLY) are calculated up to the previous byte, use or to test
      z is not changed, so it maintains whatever value it had after B
      c := bit[7]
  See "The Command Header" section of "Crow Specification v1.txt". See also page 113.
  The parsing groups are labelled by the byte being received when they execute.
}
rxFirstParsingGroup
rxH0                            test        rxByte, #%0010_1000            wz       'A - z=1 if reserved bits 3 and 5 are zero, as required
                if_nc_or_nz     mov         rxStartWait, rxParsingErrorExit         ' B - ...exit for bad reserved bits; c (bit 6) must be 1
                        if_c    mov         rxStartWait, rxParsingErrorExit         ' C - ...exit for bad reserved bit; c (bit 7) must be 0
                                mov         ina, rxByte                             ' D - save T flag in sh-ina

rxH1                            mov         payloadSize, _rxPrevByte                'A - extract payload size
                                and         payloadSize, #$7                        ' B
                                shl         payloadSize, #8                         ' C
                                or          payloadSize, rxByte                     ' D

rxH2                            mov         _rxRemaining, payloadSize               'A - _rxRemaining keeps track of how many payload bytes are left to receive
                                mov         _rxAddr, rxBufferAddrMinusOne           ' B - reset address for writing to hub
                                mov         dirb, #0                                ' C - set implicit port; dirb is port
                                mov         par, rxByte                             ' D - sh-par is token

rxH3                            test        rxByte, #%0010_0000            wz       'A - z=1 if reserved bit 5 is zero, as required
                        if_nz   mov         rxStartWait, rxParsingErrorExit         ' B - ...exit for bad reserved bit
                                mov         outb, rxByte                            ' C - preserve Crow address and mute flag; outb is CH3
                        if_nc   mov         _rxOffset, #12                          ' D - skip rxH4 and rxH5 if using implicit port
rxH4
kCrowPayloadLimit               long    2047                                        'A - spacer nop; payload size limit (11 bits in v1 and v2)
rxByte                          long    0-0                                         ' B - spacer nop; rxByte must have upper bytes zero for F16 and cont-recal
                                mov         dirb, rxByte                            ' C - start storing explicit port; dirb is port
                                shl         dirb, #8                                ' D
rxH5
lowCounterMode                  long    $3000_0000                                  'A - spacer nop; rx pin set at initialization
kOneInDField                    long    |< 9                                        ' B - spacer nop
propCrowAdminPort               long    cPropCrowID                                 ' C - spacer nop; cPropCrowID required to be two byte value
                                or          dirb, rxByte                            ' D - finished receiving explicit port; dirb is port

rxF16C0                         andn        _rxMixed, writeByteFlag                 'A - turn off writing to hub (don't write F16 bytes)
                                mov         _rxCountdown, _rxRemaining              ' B - _rxCountdown used to keep track of payload bytes left in chunk 
                                max         _rxCountdown, #128                      ' C - chunks are limited to 128 data bytes
                                sub         _rxRemaining, _rxCountdown              ' D - _rxRemaining is number of payload bytes after the coming chunk

rxF16C1                         add         _rxCountdown, #1                wz      'A - undo automatic decrement; check if _rxCountdown==0 (next chunk empty)
                        if_z    mov         rxStartWait, rxExit                     ' B - ...exit receive loop if no bytes in next chunk (all bytes received)
                                cmp         payloadSize, maxRxPayloadSize   wz, wc  ' C - check if command payload size exceeds buffer capacity
                if_nc_and_nz    or          _rxMixed, excPayloadFlag                ' D - ...if so, set flag (used in rxP_Repeat)

rxP_VerifyF16                   or          _rxMixed, writeByteFlag                 'A - turn on writing to hub
                        if_z    subs        _rxOffset, #12                          ' B - if _rxCountdown==0 then chunk's payload bytes done, go to rxF16C0
                                or          cnt, _rxF16L                    wz      ' C - should have F16U == F16L == 0; sh-cnt is rxF16U
                        if_nz   mov         rxStartWait, rxParsingErrorExit         ' D - ...exit for bad checksums

rxP_Repeat              if_z    subs        _rxOffset, #16                          'A - go to rxF16C0 if all of chunk's payload bytes are received
                        if_nz   subs        _rxOffset, #4                           ' B - ...otherwise, repeat this group
                                test        _rxMixed, excPayloadFlag        wc      ' C - check if payload size exceeds capacity (from rxF16C1)
                        if_c    mov         _rxAddr, rxBufferAddrMinusOne           ' D - ...if so, keep resetting address to prevent overrun (command discarded anyway)



{ Receive Loop Continue / Exit Instructions
    These instructions are shifted to rxStartWait in the receive loop to either receive more bytes
  or exit the loop. }
rxContinue              if_z    waitpne     rxMask, rxMask
rxExit                  if_z    jmp         #ReceiveCommandFinish
rxParsingErrorExit      if_z    jmp         #ParsingError                           'don't exit immediately -- framing error on stop bit takes precedence

{ ReceiveCommandFinish
    This code runs after all packet bytes have been received.
}
ReceiveCommandFinish
                                { save the number of low clock counts; used by cont-recal and admin commands }
                                mov         rxLowClocks, phsb

                                { verify checksums for last byte }
                                add         _rxF16L, _rxPrevByte                    'compute F16L for last byte
                                cmpsub      _rxF16L, #255                           '(computing F16U unnecessary since it should be zero)
                                or          cnt, _rxF16L                    wz      'sh-cnt is rxF16U
                        if_nz   jmp         #ParsingError                           '...bad F16

                                { extract the address }
                                mov         inb, outb                               'sh-inb used for address (scratch); outb is CH3
                                and         inb, #cAddressMask              wz      'z=1 broadcast address (0)
                                test        outb, #cMuteFlag                wc      'c=1 mute response
                    if_z_and_nc jmp         #ParsingError                           '...broadcast must mute (invalid packet)

                                { at this point the packet has passed all parsing tests, but may be addressed to different device }

rxVerifyAddress         if_nz   cmp         inb, #0-0                       wz      'verify non-broadcast address; s-field set at initialization
                        if_nz   jmp         #ReceiveCommand                         '...wrong non-broadcast address

                                { calculate the number of low bits; for both cont-recalibration and some extended admin commands }

                                shr         _rxPrevByte, #4                         'prepare to add number of low data bits for last nibble
                                movs        :lastNibble, _rxPrevByte

                                mov         rxLowBits, _rxMixed                     'get number of start bits (byteCount)
                                shl         rxLowBits, #19
                                sar         rxLowBits, #19
                                abs         rxLowBits, rxLowBits

:lastNibble                     add         _rxMixed, 0-0                           'add number of low data bits for last nibble to data bit total
 
                                mov         _y, _rxMixed                            'lowBitCount is in upper word of _rxMixed (save _rxMixed for later)
                                shr         _y, #16

                                add         rxLowBits, _y                           'byteCount + lowBitCount = num total low bits

                                { check if interbyte timeout occurred; for diagnostics }
 '                               test        _rxMixed, ibTimeoutFlag         wc
  '                      if_c    add         diagNumIBTimeouts, #1

                                { check if payload size exceeded capacity -- a reportable error condition }
                                test        _rxMixed, excPayloadFlag        wc
                        if_c    mov         _x, #cExcPayloadSize
                        if_c    mov         _page, #cReportCrowError
                        if_c    jmp         #ExecutePage

                                { check command type, exit if user command }
                                test        ina, #CommandTypeFlag           wc      'c=1 user command; sh-ina is H0 from rxH0
                        if_c    mov         _page, #cUserCommand
                        if_c    jmp         #ExecutePage

                                { check admin port - port is in dirb }

                                cmp         dirb, #0                        wz      'universal admin (port 0)
                        if_z    jmp         #UniversalAdmin

                                cmp         dirb, #1                        wz      'extended admin (port 1)
                        if_z    jmp         #ExtendedAdmin
    
                                cmp         dirb, propCrowAdminPort         wz      'PropCrow specific admin
                        if_z    mov         _page, #cPropCrowAdmin
                        if_z    jmp         #ExecutePage

                                mov         _error, #cPortNotOpen                   'the port not being open is a reportable error
                                mov         _page, #cReportCrowError
                                jmp         #ExecutePage


{ UniversalAdmin
    The universal admin commands (admin port 0) are defined in "Crow Specification v1.txt". There are
  two commands: ping and getDeviceInfo. ping will be taken care of in permanent code, while getDeviceInfo
  is done with paged code.
}
UniversalAdmin
                                { admin protocol 0 with no payload is ping }
                                cmp         payloadSize, #0                 wz      'z=1 ping command
                        if_nz   jmp         #:getDeviceInfo
                                jmp         #SendFinalResponse                      'send ping response (payloadSize==0), then go to ReceiveCommand

                                { other admin protocol 0 command, getDeviceInfo, has 0x00 as payload }
:getDeviceInfo                  cmp         payloadSize, #1                 wz      'z=0 wrong payload size for getDeviceInfo (1)
                        if_z    rdbyte      cnt, rxBufferAddr                       'load payload byte into sh-cnt
                        if_z    cmp         cnt, #$00                       wz      'z=0 wrong payload for getDeviceInfo
                        if_nz   jmp         #ReceiveCommand                         '...command not getDeviceInfo or ping

                                { perform getDeviceInfo }

                                mov         _page, #cGetDeviceInfo
                                jmp         #ExecutePage


{ ExtendedAdmin
    The extended admin protocol defines several commands on port 1. See "Crow Specification v2.txt". The keepAlive
  command is taken care of in permanent code, while the rest are done with paged code.
}
ExtendedAdmin
                                jmp         #ReceiveCommand


{ LockSharedAccess
  A call to LockSharedAcccess must be followed by a call to UnlockSharedAccess.
}
LockSharedAccess
                                or      outa, pin27
LockSharedAccess_ret            ret

{ UnlockSharedAccess
}
UnlockSharedAccess
                                andn    outa, pin27
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

:txByteLoop                     waitcnt     cnt, bitPeriod0                      'start bit
                                andn        outa, txMask

                                add         _txF16L, _txByte                    'F16 calculation
                                cmpsub      _txF16L, #255
                                add         _txF16U, _txF16L
                                cmpsub      _txF16U, #255

                                shr         _txByte, #1                 wc
                                waitcnt     cnt, bitPeriod0                      'bit0
                                muxc        outa, txMask

                                mov         inb, #6
                                add         _txAddr, #1

:txBitLoop                      shr         _txByte, #1                 wc
                                waitcnt     cnt, bitPeriod0                      'bits1-6
                                muxc        outa, txMask
                                djnz        inb, #:txBitLoop
            
                                shr         _txByte, #1                 wc
                                
                                waitcnt     cnt, bitPeriod0                      'bit7
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
txPerformChecks                 test        outb, #cMuteFlag            wc      'outb is CH3
                        if_c    jmp         SendHeader_ret
                                max         payloadSize, kCrowPayloadLimit      'do not allow payloadSize to exceed spec limit
                                
                                { compose header bytes RH0-RH2 }
                                mov         cnt, payloadSize                    'sh-cnt used for scratch
                                shr         cnt, #8                             '(assumes payloadSize does not exceed spec limit)
txApplyTemplate                 or          cnt, #0-0
                                mov         _txAddr, txScratchAddr                      
                                wrbyte      cnt, _txAddr                        'RH0
                                add         _txAddr, #1
                                wrbyte      payloadSize, _txAddr                'RH1
                                add         _txAddr, #1
                                wrbyte      par, _txAddr                        'RH2; sh-par is token

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

                                { prep for first payload chunk; the flag to indicate whether the last checksums need to be sent
                                   when FinishSending is called uses bit 9 of outb; outb is set to CH3, and will have bit 9 = 0 by default,
                                   so we don't need to clear it here (it will be set when payload bytes are sent) }
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



                                test        outb, #cMuteFlag           wc      'skip if responses muted; outb is CH3
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
                                or          outb, #cSendChecksums                   'if any payload bytes have been sent then a checksum must follow eventually

                                mov         payloadAddr, _txAddr

                        if_nz   jmp         SendPayloadBytes_ret                    'exit: chunk is not finished, but all bytes for this call have been sent 

                                { chunk is finished, but there may be more payload bytes to send, so send checksum now }

                                call        #txSendAndResetF16

                                { prep for next chunk }
                                andn        outb, #cSendChecksums                   'checksums just sent, so clear flag (bit 9 of outb)
                                mov         _txMaxChunkRemaining, #128
 
                                jmp         #:loop 

SendPayloadBytes_ret            ret


{ FinishSending (Partial Sending Routine)
  This routine finishes the response packet.
  This routine MUST be called after a call to SendFinalHeader or SendIntermediateHeader,
    even if there are no payload bytes.
}
FinishSending
                                test        outb, #cMuteFlag          wc      'skip if responses muted
                        if_c    jmp         FinishSending_ret
                                test        outb, #cSendChecksums          wc      'send final payload checksum if necessary; flag in bit 9 of outb
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
SendFinalResponse               movs        Send_ret, #ReceiveCommand

SendFinalAndReturn              mov         _x, payloadSize
                                mov         _y, payloadAddr
                                call        #SendFinalHeader
                                jmp         #_SendPayload

SendIntermediate                mov         _x, payloadSize
                                mov         _y, payloadAddr
                                call        #SendIntermediateHeader

_SendPayload                    mov         payloadSize, _x 
                                mov         payloadAddr, _y 
                                call        #SendPayloadBytes 

                                call        #FinishSending
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












{ _rxMixed Notes
    The _rxMixed register contains several pieces of information used by the receiving code:
        lowBitCount (upper word) - the count of low data bits, used by the auto-recalibration code
        E (bit 15) - flag used to detect when the command payload exceeds the buffer size, to prevent overruns
        W (bit 14) - flag used to identify which packet bytes to write to the hub (i.e. payload bytes)
        I (bit 13) - flag used to record that an interbyte timeout has occurred
        byteCount (bits 0-12) - the number of packet bytes received, as a negative number (used by auto-recal code)
    So this is the layout
        |---lowBitCount--|EWI|--byteCount--|
    Value after initial reset:
        |0000000000000000|000|1111111111111|
    Value after interbyte timeout reset:
        |0000000000000000|001|1111111111111|
    Considerations:
        - The sizes of lowBitCount and byteCount were chosen so that this mechanism will work with payload sizes
            up to 4095 bytes (the expected maximum allowed in any future Crow revisions).
        - The placement of the I flag allows the W flag mask to be used as the reset value for _rxMixed, which works
            because of the djnz at the bottom of the loop.
        - The byte count mask ($1fff), which is necessary to extract byteCount, also serves as the reset value
            for the initial pass through the receive loop.
        - The byte count is made by the djnz at the bottom of the loop -- a jump is required anyway, so the byte
            count comes for free. _rxMixed never reaches zero since the initial value exceeds any possible
            packet size (the parser enforces this limit, even if the host keeps sending bytes).
    See page 114.
}   
excPayloadFlag          long    |< 15       'flag in _rxMixed, indicates command payload exceeds buffer capacity
rxMixedTimoutReset                          'used to reset _rxMixed when an interbyte timeout has occurred
writeByteFlag           long    |< 14       'flag in _rxMixed, used by parsing code to identify payload bytes to write to hub
ibTimeoutFlag           long    |< 13       'flag in _rxMixed, used to signify that an interbyte timeout has occurred
rxMixedInitReset        long    $1fff       'used to reset _rxMixed for the first time through the receive loop
kOneInUpperWord         long    $1_0000     'used to increment lowBitCount in _rxMixed


{ ExecutePage

    The code for PropCrow exceeds the cog's space, so a paging mechanism must be used. This paging mechanism
  also makes it easier to expand the base PropCrow implementation.

    Usage:
     (mov       _retAddr, #<address to return to>)  'optional; also, set any necessary variables to pass data
      mov       _page, #<index of page>
      jmp       #ExecutePage                        'code will execute starting at the first register of the page (if no errors)
        -or-
      jmpret    _retAddr, #ExecutePage              'to resume thread (if page cooperates by respecting _retAddr)


    First, this routine checks to see if the page is already loaded. If so, it won't bother reloading it. This
  routine performs a few checks to ensure the page is valid before it will execute the code. The checks:
    - The _page index must be in the range [0, numPages).
    - The page length (from the table) must be in the range [1, cPageMaxSize].
    - The last register of the page must be "jmp #16" for two reasons: (1) there's an error handler at register 16 
      to catch and report runaway execution from the code page, (2) the register serves as a signature to confirm
      that the code is meant to be executed as a code page.

    Summary:
      - Code execution starts at the first register of the page.
      - Pages aren't reloaded if avoidable (so the code must reset itself if it self-modifies).
      - Pages are not cached back to hub (so they can't store information).
      - The page table is considered static (unlike the user ports table).
      - Any errors in the loading process will cause an error handler to be called, aborting the expected thread of execution.
}
ExecutePage
                                cmp         _page, #cNumPages           wc      'see if the page index is within bounds

:checkCurr              if_c    cmp         _page, #cInvalidPage        wz      'curr page index stored in s-field (init'ed to cInvalidPage)
                  if_c_and_z    jmp         #cPage                              'if page already loaded and is valid / in-bounds, then go

                        if_nc   mov         _error, #cPageOOB                   'page index must be within table bounds
                        if_nc   jmp         #ImplementationErrorHandler

                                movd        :load, #cPage

                                mov         _pageEntryAddr, _page               '@(PageTable[index]) = @pageTableAddr + 4*index
                                shl         _pageEntryAddr, #2
                                add         _pageEntryAddr, pageTableAddr 
                                rdword      _pageAddr, _pageEntryAddr           '_pageAddr = base address of page in hub
                                add         _pageEntryAddr, #3
                                rdbyte      _pageSize, _pageEntryAddr   wz      '_pageSize in longs

                        if_z    mov         _error, #cEmptyPage                 'page size can not be zero
                        if_z    jmp         #ImplementationErrorHandler

                                cmp         _pageSize, #cPageMaxSize    wc, wz  'page size must fit within space
                if_nc_and_nz    mov         _error, #cExcPageSize
                if_nc_and_nz    jmp         #ImplementationErrorHandler

                                movs        :verify, #cPage
                                add         :verify, _pageSize
                                sub         :verify, #1
 
:load                           rdlong      0-0, _pageAddr
                                add         :load, kOneInDField
                                add         _pageAddr, #4
                                djnz        _pageSize, #:load

                                movs        :checkCurr, _page                   'the page has been changed

:verify                         cmp         PageSignature, 0-0          wz      'verify signature (last register is "jmp #16")

                        if_z    jmp         #cPage                              'all good, so go

                                { bad signature }

                                movs        :checkCurr, #cInvalidPage           'must mark page as invalid

                                mov         _error, #cBadPageSig

                            { fall through to implementation error handler }

ImplementationErrorHandler                  
                                mov         cnt, cnt
                                add         cnt, pause
:loop                           xor         outa, pin27
                                waitcnt     cnt, pause
                                jmp         #:loop

                            { fall through to reportable error handler }

ReportError

                                jmp         #RecoveryMode


 { Constants (after initialization) }
rxMask              long    1              'shifted at initialization
txMask              long    1

pin27 long |< 27

pause long 8_000_000

PageSignature                   jmp         #16                                 'for reference, never executed


{ This is the end of permanent code. Initialization code, paged code, and res'd variables follow. }


fit cPage 'On error: permanent code exceeds space allotted. Reduce code or increase cPage.


{ FinishInit
    The initialization process started in the first 16 registers, which will be overwritten with a nibble-based
  low bit count table (for the continuous recalibration code). Initialization continues here, in the code page
  space. This code will be overwritten when the the first page is executed.

}
FinishInit
                                or          dira, pin27
                                or          outa, pin27

                                add         _addr, #1                           'txPin
                                rdbyte      _x, _addr      
                                shl         txMask, _x
                                or          outa, txMask
                               
                                add         _addr, #1                           'rxBufferAddr, rxBufferAddrMinusOne
                                rdword      rxBufferAddr, _addr 
                                mov         rxBufferAddrMinusOne, rxBufferAddr
                                sub         rxBufferAddrMinusOne, #1

                                add         _addr, #2                           'txBufferAddr
                                rdword      txBufferAddr, _addr

                                add         _addr, #2                           'maxRxPayloadSize
                                rdword      maxRxPayloadSize, _addr

                                add         _addr, #4                           'deviceInfoAddr
                                rdword      deviceInfoAddr, _addr

                                add         _addr, #2                           'pageTableAddr
                                rdword      pageTableAddr, _addr

                                add         _addr, #3                           'crowAddress
                                rdbyte      _x, _addr
                                movs        rxVerifyAddress, _x

                                add         _addr, #1                           'accessLockID
                                rdbyte      accessLockID, _addr

                                add         _addr, #1                           'cogID (written to hub)
                                cogid       _x
                                wrbyte      _x, _addr

                                add         _addr, #3                           'txScratchAddr
                                mov         txScratchAddr, _addr

                                { load low bit count table from hub into registers 0-15 (this saves a trivial amount of hub memory) }
                                mov         inb, #16
                                mov         _addr, par
                                add         _addr, #16
:loop                           rdbyte      _x, _addr
                                shl         _x, #16                             'lowBitCount is in upper word of _rxMixed (see "_rxMixed Notes")
                                mov         0-0, _x
                                add         $-1, kOneInDField
                                add         _addr, #1
                                djnz        inb, #:loop

                                { finally, execute the CalculateTimings page; it will automatically go to RecoveryMode afterwards }
                                mov         _page, #cCalculateTimings
                                jmp         #ExecutePage


fit cPageLimit 'On error: the initialization code exceeds space available. Reduce code, or increase cPage and/or cPageMaxSize.

org cPageLimit


payloadSize     res
payloadAddr     res


_rcvyCurrPhsb
_rxLastWait1
_txMaxChunkRemaining    res

_calcOptions
_page
_rxPrevByte
_rcvyPrevPhsb
_txAddr         res

_calcClk
_pageEntryAddr
_rxCountdown
_txCount        res

_calcBaud
_pageAddr
_rxMixed  
_txNextByte     res

_calcIBTimeout
_pageSize
_txByte         res

_calcBreak
_txF16L         res

_calcTwoBit
_pageTmp
_txF16U
_rxRemaining        res


{ Global Variables }
rxLowBits res
rxLowClocks res


{ Serial Timings }
'rxBitPeriodA    res
'rxBitPeriodB    res
rxBitPeriod5    res

'txBitPeriodA    res
'txBitPeriodB    res


bitPeriod0      res
bitPeriod1      res
startBitWait    res
stopBitDuration res
breakMultiple   res
recoveryTime    res
ibTimeout       res
rxPhsbReset     res

{ Constants (after initialization) }
deviceInfoAddr          res
accessLockID            res
rxBufferAddr            res
rxBufferAddrMinusOne    res
txBufferAddr            res
numUserPortsAddr        res
maxUserPorts            res
userPortsAddr           res
maxRxPayloadSize        res
txScratchAddr           res

serSettingsChangedAddr  res
pageTableAddr           res

fit 490 'On error: too many res variables. Reduce variables, cPage, or cPageMaxSize.

{ Dedicated Temporary Variables
    Some routines (Divide, Multiply, ReportCrowError) use these registers for arguments and results.
    Important: the receiving code uses these registers, so their values will be undefined
  after each command is received.
    Aliases: _tmp0 through _tmp5, or _x, _y, _z, _addr, _retAddr, and _count.
}
org 490

_tmp0
_x
_error
_rxOffset       res

_tmp1
_y 
_rxResetOffset  res

_tmp2
_z
_rxWait0    res

_tmp3
_addr
_rxWait1    res

_tmp4
_retAddr
_rxAddr     res

_tmp5
_count 
_rxF16L     res




