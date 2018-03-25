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
'cCmdBufferMaxSize   = 300 'Commands with payloads over this limit will receive OverCapacity error responses.
'cRspBufferMaxSize   = 200 'This is the limit only for the dedicated response buffer. 
cMaxUserPorts       = 10    'The maximum number of open user ports. May be any two byte value (as memory allows).

cMaxRxPayloadSize   = 300   'may be 2-2047 (lower limit due to mechanism to avoid buffer overruns)
cMaxTxPayloadSize   = 100   'may be 0-2047






cRxBufferLongs   = (cMaxRxPayloadSize/4) + 1
cTxBufferLongs   = (cMaxTxPayloadSize/4) + 1
cUserPortsLongs  = ((cMaxUserPorts*6) / 4) + 1

{ other }
cPropCrowID         = $abcd 'must be two byte value




{ Flags and Masks }

{ ...for flagsAndBadF16 - see flagsAndBadF16 Notes below }
cCommandTypeFlag    = %0_0001_0000
cSendF16Flag        = %1_0000_0000

{ ...for cmdDetails }
cAddressMask        = %0001_1111
cMuteFlag           = %0100_0000

{ ...for serialOptions }
cUseSource          = %0000_0001
cUseBaudDetect      = %0000_0010
cUseContRecal       = %0000_0100
cUseTwoStopBits     = %1000_0000

{ ...for otherOptions }
cEnableReset        = %0000_0001
cAllowRemoteChanges = %0000_0010
cSendErrorFlag      = %0000_0100

{ Paging Constants 
    These control the register layout in the cog. If you're reading this you're probably
  are getting FIT errors from the compiler.
}
cPage           = 402  'Starting address of paged code. Permanent code is below this address.
cPageMaxSize    = 52    'Maximum size of pages.
cPageLimit      = cPage + cPageMaxSize  'Res'd registers start at cPageLimit.

{ Crow Error Codes
    The Crow v2 specification introduced error responses. Error responses contain a 
  5-bit error code identifying the error. These are the error codes assigned by the
  standard.
}
cDeviceUnavailable      = 0
cPayloadTooBig          = 1
cBadPayloadChecksum     = 2
cPortNotOpen            = 3
cIsBusy                 = 4
cLowResources           = 5
cImplementationFault    = 6
cUserCodeFault          = 7

{ Custom Error Codes
    These must be 32-63.
}
cDriverLocked           = 32


{ StringTable Entries }
cPropCrowStr        = 0
cWaitingForStr      = 1
cToFinishStr        = 2
cUnknownErrStr      = 3


{ page indices }
cCalculateTimings   = 0
cGetDeviceInfo      = 1
cUserCommand        = 2
cPropCrowAdmin      = 3
cSendError          = 4
cBlinky             = 5
cOtherStandardAdmin = 6
cCalc2              = 7
cCalc3              = 8
cSendCustomError    = 9
cSendErrorFinish    = 10
cNumPages           = 11



cInvalidPage        = 511   'signifies no valid page loaded


{ Special Purpose Register Usage
    Out of necessity PropCrow makes use of some special purpose registers for variables. 
    Variables aliased to shadow SPRs have a "_SH" suffix as a warning to use them only in the d-field.
    The counter A and video generator registers are never used by PropCrow -- they have been left
  available for custom code.
}

{ SPR Global Variables }

flagsAndBadF16  = $1F7      'dirb       see flagsAndBadF16 Notes
port_SH         = $1F0      'sh-par
cmdDetails      = $1F5      'outb       cmdDetails is CH3
token_SH        = $1F2      'sh-ina

{ SPR Local Variables }

_txWait_SH      = $1F1      'sh-cnt
_rxF16U_SH      = $1F1      'sh-cnt

_copyTmp_SH     = $1F3
_pageTmp_SH     = $1F3      'sh-inb
_txTmp_SH       = $1F3      'sh-inb
_rxTmp_SH       = $1F3      'sh-inb



{ flagsAndBadF16 Notes
    Like _rxMixed, this register contains several pieces of information:
        commandType - bit 4 - 0 = admin command, 1 = user command. From CH0. Use #cCommandTypeFlag to test.
        sendF16 - bit 9 - Flag used by the partial sending routines to signify if the last payload F16 bytes need to
                          be sent. Use #cSendF16Flag flag to test. Cleared when a command arrives.
        isOpen - bit 13 - Flag indicates if a transaction is open. It is cleared when a command arrives, so
                          the code must set it later if required. Use isOpenFlag to test.
        badF16Count - upper word - A count of the number of payload chunks that have failed checksums.
                                   Resets to zero when a command arrives. 
    flagsAndBadF16 is set to CH0 in the shifted parsing code (instruction A of RxH0), which then
  modifies it to test the reserved bits. Because of this source, bits 0-3 and bits 5-7 should be
  considered undefined. The upper bytes will be all zeroes since this is always true of rxByte.
}


obj
    peekpoke : "PeekPoke"


var

    long    __userPorts[cUserPortsLongs]
    long    __rxBuffer[cRxBufferLongs]
    long    __txBuffer[cTxBufferLongs]


pub new | pause

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
    word[@PageTable][8] := @SendErrorPg
    word[@PageTable][10] := @Blinky
    word[@PageTable][12] := @OtherStandardAdmin
    word[@PageTable][14] := @Calc2
    word[@PageTable][16] := @Calc3
    word[@PageTable][18] := @SendCustomErrorPg
    word[@PageTable][20] := @SendErrorFinishPg

    word[@StringTable][0] := @PropCrowStr
    word[@StringTable][2] := strsize(@PropCrowStr)
    word[@StringTable][4] := @WaitingForStr
    word[@StringTable][6] := strsize(@WaitingForStr)
    word[@StringTable][8] := @ToFinishStr
    word[@StringTable][10] := strsize(@ToFinishStr)
    word[@StringTable][12] := @UnknownErrStr
    word[@StringTable][14] := strsize(@UnknownErrStr)



    __string0Addr := @ImplErrorStart
    __string0Size := strsize(@ImplErrorStart)


    __numUserPorts      := 3
    __userPorts.word[0] := 0
    __userPorts.word[3] := 1
    __userPorts.word[6] := 78

    __userPortsAddr     := @__userPorts
    __rxBufferAddr      := @__rxBuffer
    __txBufferAddr      := @__txBuffer
    __datConstantsAddr  := @DatConstants
    __pageTableAddr     := @PageTable

    __objBaseAddr       := @@0

    cognew(@Entry, @ControlBlock)

    pause := 160_000_000
    result := cnt

    repeat
        __lockingUser := 0
        outa[26] := 1
        waitcnt(result += pause)
        __lockingUser := 1040
        outa[26] := 0
        waitcnt(result += pause)

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

'4: SendError
word    0
byte    0
byte    SendErrorPg_end - SendErrorPg + 1

'5: Blinky
word    0
byte    0
byte    Blinky_end - Blinky + 1


'6: OtherStandardAdmin
word    0
byte    0
byte    OtherStandardAdmin_end - OtherStandardAdmin + 1

'7: Calc2
word    0
byte    0
byte    Calc2_end - Calc2 + 1

'8: Calc3
word    0
byte    0
byte    Calc3_end - Calc3 + 1

'9: SendCustomError
word    0
byte    0
byte    SendCustomErrorPg_end - SendCustomErrorPg + 1

'10: SendErrorFinish
word    0
byte    0
byte    SendErrorFinishPg_end - SendErrorFinishPg + 1

  
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
      25   1    I    otherOptions, bitfield
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
      56   2         lockingUser (address of user block)
      58   2    -    -
     (60)

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
__controlBlock
                    long    115200              'activeBaudrate
                    word    250                 'activeInterbyteTimeout, in milliseconds
                    word    100                 'activeBreakThreshold, in milliseconds
                    long    $0707_0101          'activeSerialOptions
                    long    115200              'resetBaudrate
                    word    250                 'resetInterbyteTimeout, in milliseconds
                    word    100                 'resetBreakThreshold, in milliseconds
                    long    $0707_0101          'resetSerialOptions
                    byte    0                   'activeSerialSettingsChanged
                    byte    cSendErrorFlag | cAllowRemoteChanges | cEnableReset                   'otherOptions
__numUserPorts      word    0                   'numUserPorts
                    word    cMaxUserPorts       'maxUserPorts
__userPortsAddr     word    0-0                 'userPortsAddr
__rxPin             byte    31                  'rxPin
__txPin             byte    30                  'txPin
__rxBufferAddr      word    0-0                 'rxBufferAddr
__txBufferAddr      word    0-0                 'txBufferAddr
                    word    cMaxRxPayloadSize   'maxRxPayloadSize
                    word    cMaxTxPayloadSize   'maxTxPayloadSize
__datConstantsAddr  word    0-0                 'datConstantsAddr
__pageTableAddr     word    0-0                 'pageTableAddr
                    byte    cNumPages           'numPages
                    byte    1                   'crowAddress
                    byte    255                 'accessLockID
                    byte    0-0                 'cogID
__objBaseAddr       word    0-0                 'objBaseAddr
                    long    0                   'txScratch
__lockingUser       word    0
                    word    0


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
long    $0000_0200 | ((cPropCrowID & $ff) << 24) | ((cPropCrowID & $ff00) << 8)             'Crow v2, implementationID = cPropCrowID
long    $0002_0000 | ((cMaxRxPayloadSize & $ff) << 8) | ((cMaxRxPayloadSize & $700) >> 8)   'max commmand payload size, 2 admin ports (upper byte not sent from here) 
long    $0000_0000 | ((cPropCrowID & $ff) << 24) | ((cPropCrowID & $ff00) << 8)             'admin ports 0 and PropCrowID

{ NibbleTable (@DatConstants + 12)
  A table of low bit counts for integers 0 to 15. Used for continuous recalibration.
}
byte 4, 3, 3, 2, 3, 2, 2, 1, 3, 2, 2, 1, 2, 1, 1, 0

{ StringTable (@DatConstants + 28)
}
StringTable

'0 - PropCrowSpaceStr
word    0
word    0

'1 - WaitingForStr
long 0

'2 - ToFinishStr
long 0

'3 - UnknownErrStr
long 0


{ ErrorResponseTemplate 
    This template sets up an error response with no standard details, and one implementation provided
  ascii error message. After writing this template to the response buffer, all that remains is to set
  the first byte (type OR'd with 0x40), set byte 8 to message length (assuming it is less than 256),
  and write the message at byte 9 (terminating NUL not required).
} 
ErrorResponseTemplate
long    $0003_00FF      'bottom byte written later
long    $0009_0001      'top byte of message length is zero (assume all messages are less than 256 characters)

{ Strings }
PropCrowStr     byte "PropCrow", 0
WaitingForStr   byte "Waiting for ", 0
ToFinishStr     byte " to finish.", 0
UnknownErrStr   byte "Unknown error.", 0
dat

org cPage
OtherStandardAdmin
                                { todo }
OtherStandardAdmin_end          
                                jmp         #RecoveryMode
fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.

org cPage
Blinky

                                mov         inb, #12
 
                                mov         cnt, cnt
                                add         cnt, blinkyPause

:loop                           xor         outa, pin27
                                waitcnt     cnt, blinkyPause
                                djnz        inb, #:loop

                                jmp         #RecoveryMode
Blinky_end 
blinkyPause     long 4_000_000


{ PgSendErrorResponse
    This page starts the process of sending a Crow-level error response (not an upper-level protocol error response).
  Crow-level error responses indicate some problem that prevents an otherwise valid command from being responded to normally.
  Error responses are sent only for 'reportable' errors -- some errors have to be silently ignored (e.g. bad
  reserved bits in the command header, or errors for any command with muted responses). See the Crow v2
  specification for more details.
    To report an error: set _x to the error number, then jump to ErrorHandler. That routine will determine whether
  the error response should be sent, in which case it will execute this page.
    Some errors require _y to be set as well. A list:
        cDriverLocked: _y = lockingUser (user code block address)
}
org cPage
SendErrorPg
                                { It is assumed that _x has been set to a standard error number (< 32) or a custom error number (32-63).
                                  If _x is a standard error number then the error response will include no implementation
                                    specific error details (i.e. no ascii message).
                                  Custom errors will include an ascii error message, and the custom error number will
                                    be translated to a standard error number.
                                  Custom errors may require _y be set to some value. }

                                { The entire payload will be composed in the response buffer and sent on the SendErrorFinish page. }

                                { Is the error number a standard error number? Custom errors on separate page. }
                                cmp         _x, #31                     wc
                        if_nc   mov         _page, #cSendCustomError
                        if_nc   jmp         #ExecutePage

                                { If a standard error number was passed (_x < 32) we will not include any implementation
                                    specific details. This means E1 and E2 are undefined and can be skipped. }
                                mov         _copyDestAddr, #3

                                { If no standard details are included we will send a minimal response payload. }
                                mov         _count, #1

                                { PayloadTooBig sends the supported max size (two bytes) as a standard detail. }
                                cmp         _x, #cPayloadTooBig         wz
                        if_z    and         _x, #%0100_0000                     'standard details are included
                        if_z    add         _count, #4                          '+2 for E1-E2, +2 for details
                        if_z    mov         _copySrcAddr, deviceInfoAddr
                        if_z    add         _copySrcAddr, #4
                        if_z    mov         _copyCount, #2                      'copy from device info template
                        if_z    call        #CopyBytes

                                { PortNotOpen sends type (one byte: 0x00=admin, 0x01=user) and port number (2 bytes). }
                                cmp         _x, #cPortNotOpen                   wz
                        if_z    and         _x, #%0100_0000                         'standard details are included
                        if_z    add         _count, #5                              '+2 for E1-E2, +3 for details
                        if_z    test        flagsAndBadF16, #cCommandTypeFlag   wc
                    if_z_and_c  wrbyte      :one, _copyDestAddr                     ':one has one in bottom byte 
                    if_z_and_nc wrbyte      kOneInDField, _copyDestAddr             'kOneInDField has bottom byte zero
:one                    if_z    add         _copyDestAddr, #1
                        if_z    ror         port_SH, #8
                        if_z    wrbyte      port_SH, _copyDestAddr                  'port MSB
                        if_z    add         _copyDestAddr, #1
                        if_z    rol         port_SH, #8
                        if_z    wrbyte      port_SH, _copyDestAddr                  'port LSB
                        if_z    add         _copyDestAddr, #1

                                mov         _page, #cSendErrorFinish
SendErrorPg_end                 jmp         #ExecutePage
fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.

{ SendCustomErrorPg
    Executed if _x is not a standard error number (< 32). Such numbers are used to indicate that an ascii 
  error message should be included, and the custom error number translated to a standard error number.
}
org cPage
SendCustomErrorPg
                                { Currently, all custom errors have no standard details, and just one implementation detail (the
                                    ascii message). This makes things relatively simple:
                                        - copy the template
                                        - compose the message starting at byte 9
                                        - write message length at byte 8 (requires length < 256), NUL not required
                                        - set _count = message length + 9
                                        - make sure _x has form 0x80 OR'd with some valid Crow error type }
                                
                                { Start by copying the template to the response buffer. }
                                mov         _copyDestAddr, txBufferAddr
                                mov         _copySrcAddr, deviceInfoAddr
                                add         _copySrcAddr, #(ErrorResponseTemplate - DatConstants)
                                mov         _copyCount, #8
                                call        #CopyBytes

                                { At this point _copyDestAddr points to byte 9 of buffer. At first _count will hold the message
                                    length, at :finish it will become the payload size. }

                                { _copyMaxSize applies to the CopyString* routines. It should be larger than any expected string
                                    fragment, but small enough that the message length can be guaranteed to be less than 256. }
                                mov         _copyMaxSize, #40

                                cmp         _x, #cDriverLocked          wz
                        if_nz   jmp         #:unknownCustom

:isLocked                       { Driver is locked. }
           
                                { Report as IsBusy. }
                                mov         _x, #cIsBusy 

                                { Message = "Waiting for <object name> to finish." }

                                { "Waiting for " }
                                mov         _copyIndex, #cWaitingForStr
                                call        #CopyStringFromTable
                                mov         _count, _copySize
                                sub         _copyDestAddr, #1

                                { <object name> }

                                { " to finish." }
                                mov         _copyIndex, #cToFinishStr
                                call        #CopyStringFromTable
                                add         _count, _copySize

                                jmp         #:finish

:unknownCustom                  mov         _x, #cImplementationFault
                                mov         _copyIndex, #cUnknownErrStr
                                call        #CopyStringFromTable
                                mov         _count, _copySize

:finish
                                { Write the message length to byte 8. }
                                mov         _addr, rxBufferAddr
                                add         _addr, #8
                                wrbyte      _count, _addr
            
                                { Make _count the payload length. }
                                add         _count, #9

                                { Set bit 7 (I flag) of E0 for implementation details. }
                                or          _x, #%1000_0000
                               
                                mov         _page, #cSendErrorFinish
SendCustomErrorPg_end           jmp         #ExecutePage 
fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.


{ SendErrorFinishPg
    Executed at the very end of preparing an error response, when it is almost ready to be sent.
}
org cPage
SendErrorFinishPg
                                { Write first byte of response payload. }
                                mov         _addr, txBufferAddr
                                wrbyte      _x, _addr
                
                                { Both _count and _addr ready, so send. }
SendErrorFinishPg_end           jmp         #SendFinalResponse
fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.


{ UserCommandPg
}
org cPage
UserCommand

                                'mov         payloadAddr, rxBufferAddr
                                'jmp         #SendFinalResponse


                                rdlong      _x, rxBufferAddr
                                jmp         #ErrorHandler

{
                                'echo the port
                                mov         _x, dirb
                                wrword      _x, txBufferAddr
                                mov         payloadSize, #2
                                mov         payloadAddr, txBufferAddr
}

                                'report calibration observations
                                mov         _addr, txBufferAddr
                                wrlong      cmdLowBits, _addr
                                add         _addr, #4
                                wrlong      cmdLowClocks, _addr
                                add         _addr, #4
                                wrlong      _rxLastWait1, _addr

                                mov         _x, cmdLowClocks 
                                mov         _y, cmdLowBits
                                call        #Divide
                                add         _addr, #4
                                wrlong      _y, _addr

                                mov         _count, #16
                                mov         _addr, rxBufferAddr

UserCommand_end                 jmp         #SendFinalResponse
fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.


org cPage
PropCrowAdmin
                                mov         _addr, #0
                                mov         _count, #8
PropCrowAdmin_end               jmp         #SendFinalResponse
fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.

org cPage
GetDeviceInfo
                                'call        #LockSharedAccess


                                rdword      _x, numUserPortsAddr                    '_x = num open user ports to report
                                max         _x, #255                                'getDeviceInfo limited to reporting 255 user ports

                                mov         _count, _x                         'response payload size is 12 + 2*<num user ports> (assumes 2 admin protocols)
                                shl         _count, #1
                                add         _count, #12
                                call        #SendFinalHeader

                                mov         _addr, deviceInfoAddr
                                mov         _count, #7
                                call        #SendPayloadBytes                       'send up to num reported user ports

                                wrbyte      _x, txBufferAddr
                                mov         _addr, txBufferAddr
                                mov         _count, #1
                                call        #SendPayloadBytes                       'send number of reported user ports

                                mov         _addr, deviceInfoAddr
                                add         _addr, #8
                                mov         _count, #4
                                call        #SendPayloadBytes                       'send open admin ports from template

                                cmp         _x, #0                   wz
                        if_z    jmp         #:finish                                '...skip if no user ports

                                mov         _addr, userPortsAddr              'send the user port numbers directly from the table
                                sub         _addr, #5

:loop                           add         _addr, #6                         'MSB             
                                mov         _count, #1
                                call        #SendPayloadBytes
                                sub         _addr, #2                         'LSB
                                mov         _count, #1
                                call        #SendPayloadBytes

                                djnz        _x, #:loop       

:finish                         call        #FinishSending
 
                                'call        #UnlockSharedAccess
                                
GetDeviceInfo_end               jmp         #ReceiveCommand
fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.



org cPage

{ CalculateTimings
  This routine calculates the serial timings (in clocks) based on the settings stored in the hub.
}
CalculateTimings
                                'call        #LockSharedAccess

                                mov         _addr, par
                                rdlong      _calcBaud, _addr
                                add         _addr, #4
                                rdword      _calcIBTimeout, _addr
                                add         _addr, #2
                                rdword      _calcBreak, _addr
                                add         _addr, #2
                                rdlong      _calcOptions, _addr
                                rdlong      _calcClk, #0

                                'call        #UnlockSharedAccess

                            
                                mov         _x, _calcClk                    
                                shl         _x, #1
                                mov         _y, _calcBaud
                                call        #Divide
                                mov         _calcTwoBit, _y

                                mov         bitPeriod0, _calcTwoBit
                                shr         bitPeriod0, #1
                                min         bitPeriod0, #34                         'bitPeriod0 ready
                           
                                mov         txBitPeriodA, bitPeriod0
 
                                mov         bitPeriod1, bitPeriod0
                                test        _calcTwoBit, #1                     wc
                        if_c    add         bitPeriod1, #1                          'bitPeriod1 ready

                                mov         txBitPeriodB, bitPeriod1

                                'mov         rxBitPeriod5, bitPeriod0
                                'min         rxBitPeriod5, #33

                                mov         startBitWait, bitPeriod0
                                shr         startBitWait, #1
                                sub         startBitWait, #10                       'startBitWait ready; must not be < 5 (won't if bitPeriod0 >= 34)
            
                                mov         _page, #cCalc2

CalculateTimings_end
                                jmp         #ExecutePage

fit cPageLimit 'Page is too big. Reduce code or increase cPageSize.



org cPage
Calc2
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

                                mov         _page, #cCalc3
                                jmp         #ExecutePage

Calc2_end
k1000                           long    1000

fit cPageLimit 'On error: page is too big. Reduce code or increase cPageSize.


org cPage
Calc3 

                                { rxPin and txPin are one byte values in the control block. txPin is immediately
                                    after rxPin. }

                                mov         _addr, par                          'rxPin
                                add         _addr, #(__rxPin - __controlBlock)
                                rdbyte      _x, _addr
                                mov         rxMask, #1
                                shl         rxMask, _x
                                movs        ctrb, _x
                                'movs        lowCounterMode, _x
                                'mov         ctrb, lowCounterMode

                                add         _addr, #1                           'txPin (immediately after rxPin)
                                rdbyte      _x, _addr
                                mov         txMask, #1
                                shl         txMask, _x 
                                or          outa, txMask

                                add         _addr, #1                           'txPin
                                rdbyte      _x, _addr      
                                mov         txMask, #1
                                shl         txMask, _x
                                or          outa, txMask
                               
Calc3_end                       jmp         #RecoveryMode
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
                                'rdbyte      _x, _addr
                                'shl         rxMask, _x
                                'movs        lowCounterMode, _x
                                '_xmov         ctrb, lowCounterMode

                                { Setup rx low counter. }
                                mov         frqb, #1              
                                mov         ctrb, lowCounterMode            'pin number written in LoadSettings

                                jmp         #FinishInit


long 0[16-$]
fit 16
org 16

{ Multiply
    Algorithm from the Spin interpreter, with sign code removed.
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
    Algorithm from the Spin interpreter, with sign code removed.
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



                                
{ ReceiveCommand
  This routine contains the receive loop used to receive and process bytes. Processing is done using
    shifted parsing instructions, which are explained in more detail in the "Parsing Instructions" 
    section below.
}
ReceiveCommand

                                { pre-loop initialization }
                                mov         rxStartWait, rxContinue
                                movs        rxMovA, #rxFirstParsingGroup
                                movs        rxMovB, #rxFirstParsingGroup+1
                                movs        rxMovC, #rxFirstParsingGroup+2
                                movs        rxMovD, #rxFirstParsingGroup+3
                                mov         _rxResetOffset, #0
                                mov         _rxWait0, startBitWait

                                test        rxMask, ina                     wz      'z=1 => rx pin already low -- missed falling edge

                        if_nz   waitpne     rxMask, rxMask                          'wait for start bit edge
                        if_nz   add         _rxWait0, cnt
                        if_nz   waitcnt     _rxWait0, bitPeriod0                    'wait to sample start bit
                        if_nz   test        rxMask, ina                     wc      'c=1 framing error; c=0 continue, with parser reset
                        if_z    jmp         #RecoveryMode                           '...exit for missed falling edge (need edge for accurate cont-recal)
                        if_c    jmp         #FramingError

                                { the receive loop -- c=0 reset parser}

'loop top - occurs within interval between startbit and bit0
rxLoopTop
                        if_nc   mov         _rxMixed, rxMixedReset                  'Mixed - reset byteCount, lowBitCount, writeVetoes (nonPayloadFlag is set)
                       
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
                        if_nc   mov         _rxF16U_SH, #0                          'F16 2
                        if_c    add         _rxF16L, _rxPrevByte                    'F16 3 - this if_c is not optional (_rxPrevByte undefined on reset, esp. high bytes)
                        if_c    cmpsub      _rxF16L, #255                           'F16 4 - the if_c's are optional from this point on for F16
                        if_c    add         _rxF16U_SH, _rxF16L                     'F16 5 - (Note on above: _rxPrevByte must have upper bytes zero for this calculation
                        if_c    cmpsub      _rxF16U_SH, #255                        'F16 6 -  to work, which is not necc. true the first pass through, but is after.)

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
                                test        _rxMixed, writeVetoesMask       wz      'Write 1 - z=1 write byte to hub if all writeVetoes are clear
                        if_z    add         _rxAddr, #1                             'Write 2 - increment address (pre-increment saves re-testing the flag)

'bit 5 - 33 clocks
rxBit5                          waitcnt     _rxWait1, bitPeriod0
                                test        rxMask, ina                     wc
rxHubop                         long    0-0                                         'Hubop - Write 3 (rxWriteByte -- uses z flag), or rxReadDriverLock)

'bit 6 - 34 clocks
rxBit6                          waitcnt     _rxWait1, bitPeriod1
                                testn       rxMask, ina                     wz
                                muxc        rxByte, #%0010_0000
                                muxz        rxByte, #%0100_0000
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

rxStartWait                     long    0-0                                         'wait for start bit, or exit loop (either all bytes received, or parsing error)

                        if_z    add         _rxWait0, cnt                           'Wait 1

'start bit - 34 clocks (last instr at rxLoopTop)
rxStartBit              if_z    waitcnt     _rxWait0, bitPeriod0
                        if_z    test        rxMask, ina                     wz      'z=0 framing error
rxAddUpperNibble        if_z    add         _rxMixed, 0-0                           'Cont-Recal 8 - finish adding low bit count for upper nibble of previous byte
                        if_z    mov         _rxTmp_SH, _rxWait0                     'Timeout 1
                        if_z    sub         _rxTmp_SH, _rxWait1                     'Timeout 2 - see page 98 for timeout notes
                        if_z    cmp         _rxTmp_SH, ibTimeout            wc      'Timeout 3 - c=0 reset, c=1 no reset
                        if_z    djnz        _rxMixed, #rxLoopTop                    'Mixed - add to byteCount (negative)
                    
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




{ RX Hubop, used by ReceiveCommand
    These instructions are shifted into the receive loop at the rxHubop location. The shifts must be performed
  by the shifted parsing code -- they are not done automatically.
    It does not matter which instruction is loaded on parser reset. Consider each case:
      RxWriteByte - On parser reset the nonPayloadFlag in writeVetoes (in _rxMixed) is set, so writes will not occur.
      RxReadDriverLock - Reading the driver lock state is OK -- it is intended behavior during header arrival.
    Also, rxHubop is a nop on cog launch, so the pre-loop initialization code does not ever need to set its value.
    For consideration: there's the potential for supporting a pool of buffers using the RX Hubop mechanism.
  This may be useful if the host is receiving DeviceUnavailable errors due to user code not releasing the driver
  lock fast enough. In this case there would be three hubops: loading the next buffer set to use, checking
  if it is locked/owned, and then setting the buffer write instruction.
}
RxReadDriverLock                rdword      _rxLockingUser, driverLockAddr          'check if user code has driver lock (will be zero if unlocked)
RxWriteByte             if_z    wrbyte      _rxPrevByte, _rxAddr                    'Write 4 - write byte to command payload buffer (if writeVetoes are clear) 




{ RX Shifted Parsing Instructions, used by ReceiveCommand

    todo: update -- some of these rules have changed

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
rxH0                            mov         flagsAndBadF16, rxByte                  'A - save T flag, reset other flags, and reset badF16Count; also prep for testing CH0
                                xor         flagsAndBadF16, #%0100_0000             ' B - flip bit 6 for reserved bits testing
                                test        flagsAndBadF16, #%0110_1000     wz      ' C - test reserved bits 3 (0), 5 (0), and 6 (originally 1); z=1 OK
                    if_nz_or_c  mov         rxStartWait, rxParsingErrorExit         ' D - ...exit for bad reserved bits (also require c = bit 7 = 0) 

rxH1                            mov         payloadSize, _rxPrevByte                'A - extract payload size
                                and         payloadSize, #$7                        ' B
                                shl         payloadSize, #8                         ' C
                                or          payloadSize, rxByte                     ' D

rxH2                            mov         _rxRemaining, payloadSize               'A - _rxRemaining keeps track of how many payload bytes are left to receive
                                mov         _rxAddr, cmdBufferResetAddr             ' B - reset address for writing command payload to hub
                                mov         port_SH, #0                             ' C - set implicit port 0
                                mov         token_SH, rxByte                        ' D - save token for responses
rxH3
                                mov         rxHubop, RxReadDriverLock               'A - read the driver's lock state
isOpenFlag
nonPayloadFlag                  long    |< 13                                       ' B - (spacer nop) part of writeVetoes in _rxMixed; also used for flagsAndBadF16
                                mov         cmdDetails, rxByte                      ' C - save CH3 for later processing (address, mute flag, reserved bit 5)
                        if_nc   mov         _rxOffset, #12                          ' D - c = bit7 = 1 for explicit port; skip H4 and H5 if using implicit port
rxH4_Optional
kCrowPayloadLimit               long    2047                                        'A - (spacer nop) payload size limit is 11 bits in v1 and v2
rxByte                          long    0-0                                         ' B - (spacer nop) rxByte must have upper bytes zero for F16 and cont-recal
                                mov         port_SH, rxByte                         ' C - start saving explicit port
                                shl         port_SH, #8                             ' D
rxH5_Optional
kOneInUpperWord                 long    $0001_0000                                  'A - (spacer nop) used to increment upper word counts lowBitCount and badF16Count
kOneInDField                    long    |< 9                                        ' B - (spacer nop) 
propCrowAdminPort               long    cPropCrowID                                 ' C - (spacer nop) cPropCrowID required to be two byte value
                                or          port_SH, rxByte                         ' D - finished saving explicit port

rxH6_F16C0                      mov         _rxCountdown, _rxRemaining              'A - _rxCountdown used to keep track of payload bytes left in chunk 
                                max         _rxCountdown, #128                      ' B - chunks are limited to 128 data bytes
                                sub         _rxRemaining, _rxCountdown              ' C - _rxRemaining is number of payload bytes after the coming chunk
                                add         _rxCountdown, #1                        ' D - pre-undo automatic decrement for F16C1
rxH7_F16C1
                        if_z    mov         rxStartWait, rxExit                     'A - ...exit receive loop if no bytes in first chunk (empty payload)
                                mov         rxHubop, RxWriteByte                    ' B - setup to write payload byte to buffer
                                cmp         _rxLockingUser, #0              wz      ' C - test if the driver is locked; z=0 driver locked by _rxLockingUser
                                muxnz       _rxMixed, driverLockedFlag              ' D - veto all buffer writes if driver is locked

{ rxP_0 - first payload byte of first chunk }
rxP_0                   if_z    mov         _rxOffset, #8                           'A - go to rxP_F16C0 if all of chunk's bytes have been received
                                andn        _rxMixed, nonPayloadFlag                ' B - clear the non-payload byte write veto (want to write payload byte to buffer)
                                or          _rxF16U_SH, _rxF16L             wz      ' C - check header's F16; z=1 OK (need F16U == F16L == 0)
                        if_nz   mov         rxStartWait, rxParsingErrorExit         ' D - ...exit for bad header checksums

{ rxP_Repeating - any payload byte after the first in a chunk }
rxP_Repeating           if_nz   mov         _rxOffset, #0                           'A - keep repeating if payload bytes in chunk (automatically go to RxP_F16C0 otherwise)
writeVetoesMask                 long    $e000                                       ' B - (spacer nop) used for _rxMixed
                                cmp         payloadSize, cmdBufferMaxSize   wz, wc  ' C - check if command payload size exceeds buffer capacity
                if_nc_and_nz    or          _rxMixed, tooBigFlag                    ' D - veto all remaining payload buffer writes if payload exceeds capacity

{ rxP_F16C0 - F16 C0 for a payload chunk }
rxP_F16C0                       or          _rxMixed, nonPayloadFlag                'A - turn off writing to payload buffer (don't write F16 bytes)
                                mov         _rxCountdown, _rxRemaining              ' B - _rxCountdown used to keep track of payload bytes left in chunk 
                                max         _rxCountdown, #128                      ' C - chunks are limited to 128 data bytes
                                sub         _rxRemaining, _rxCountdown              ' D - _rxRemaining is number of payload bytes after the coming chunk

{ rxP_F16C1 - F16 C1 for a payload chunk }
rxP_F16C1                       add         _rxCountdown, #1                wz      'A - undo automatic decrement; check if _rxCountdown==0 (next chunk empty)
                        if_z    mov         rxStartWait, rxExit                     ' B - ...exit receive loop if no bytes in next chunk (all bytes received)
driverLockedFlag                long    |< 14                                       ' C - (spacer nop) part of writeVetoes in _rxMixed
tooBigFlag                      long    |< 15                                       ' D - (spacer nop) part of writeVetoes in _rxMixed

{ rxP_CheckF16 - first payload byte in chunk, after the first chunk }
rxP_CheckF16            if_z    subs        _rxOffset, #12                          'A - go to rxP_F16C0 if all chunk payload bytes have been received
                        if_nz   subs        _rxOffset, #16                          ' B - otherwise, go to rxP_Repeating 
                                or          _rxF16U_SH, _rxF16L             wz      ' C - check chunk's F16; z=1 OK (need F16U == F16L == 0)
                        if_nz   add         flagsAndBadF16, kOneInUpperWord         ' D - increment badF16Count if chunk failed test



{ Receive Loop Continue / Exit Instructions
    These instructions are shifted to rxStartWait in the receive loop to either receive more bytes
  or exit the loop. }
rxContinue              if_z    waitpne     rxMask, rxMask
rxExit                  if_z    jmp         #ReceiveCommandFinish
rxParsingErrorExit      if_z    jmp         #ParsingError                           'don't exit at error point -- framing error on stop bit takes precedence

{ ReceiveCommandFinish
    This code runs after all packet bytes have been received.
}
ReceiveCommandFinish

                            xor outa, pin27

                                { save the number of low clock counts; used by cont-recal and admin commands }
                                mov         cmdLowClocks, phsb

                                { check final checksums }
                                add         _rxF16L, _rxPrevByte                    'compute F16L for last byte
                                cmpsub      _rxF16L, #255                           '(computing F16U unnecessary since it should be zero)
                                or          _rxF16U_SH, _rxF16L             wz      'z=1 OK (need F16U == F16L == 0)

                                { what to do for a bad final checksum (z=0) depends on whether it is for header or payload chunk }
                        if_nz   cmp         payloadSize, #1                 wc      'c=1 empty payload => F16 is header's
                if_nz_and_c     jmp         #ParsingError                           '...exit: bad header F16 is a parsing error
                        if_nz   add         flagsAndBadF16, kOneInUpperWord         'if last payload chunk is bad, increment badF16Count; deal with it later

                                { Verify reserved bit 5 of CH3 is zero. In future Crow versions this may be used for a CRC option. }
                                test        cmdDetails, #%0010_0000         wc      'c=1 out of spec
                        if_c    jmp         #ParsingError

                                { extract the address }
                                mov         _rxTmp_SH, cmdDetails                   'get address in _rxTmp
                                and         _rxTmp_SH, #cAddressMask        wz      'z=1 broadcast address (address 0)
                                test        cmdDetails, #cMuteFlag          wc      'c=1 mute response
                    if_z_and_nc jmp         #ParsingError                           '...exit: broadcast must mute (invalid packet)

                                { At this point the packet has passed all parsing tests involving non-reportable errors. }
                                { z=1 broadcast address, _rxTmp is address }

rxVerifyAddress         if_nz   cmp         _rxTmp_SH, #0-0                 wz      'verify non-broadcast address; s-field set by LoadSettings
                        if_nz   jmp         #ReceiveCommand                         '...exit: packet intended for different device

                                { Now determine if a Crow transaction is open -- it is if responses aren't muted (c=0). The
                                    transaction closes when a final response is sent, or an interruption occurs.
                                  We need to set the isOpen flag of flagsAndBadF16. Also, if a transaction is open
                                    we need to retain the line (make tx pin an output).
                                  Since this is the only place a transaction can be opened we handle the details here. A transaction
                                    can close in multiple places, so that is handled with a routine (CloseTransaction). }
                                muxnc       flagsAndBadF16, isOpenFlag              'set isOpen flag (c=0 open transaction)
                        if_nc   or          dira, txMask                            'if open, retain the line (make tx pin an output) 



'                                { calculate the number of low bits }
'
'                                shr         _rxPrevByte, #4                         'prepare to add number of low data bits for last nibble
'                                movs        :lastNibble, _rxPrevByte
'
'                                mov         rxLowBits, _rxMixed                     'get number of start bits (byteCount)
'                                shl         rxLowBits, #19
'                                sar         rxLowBits, #19
'                                abs         rxLowBits, rxLowBits
'
':lastNibble                     add         _rxMixed, 0-0                           'add number of low data bits for last nibble to data bit total
' 
'                                mov         _y, _rxMixed                            'lowBitCount is in upper word of _rxMixed (save _rxMixed for later)
'                                shr         _y, #16
'
'                                add         rxLowBits, _y                           'byteCount + lowBitCount = num total low bits


                                { do continuous recalibration, if selected }
                    
                                { todo }

                                { now check some reportable error conditions }
rxErrorChecks 
                                { error check: the driver is/was locked by user code }
                                test        _rxMixed, driverLockedFlag      wc
                        if_c    mov         _x, #cIsBusy
                        if_c    jmp         #ErrorHandler

                                { error check: payload size exceeded capacity }
                                test        _rxMixed, tooBigFlag            wc
                        if_c    mov         _x, #cPayloadTooBig
                        if_c    jmp         #ErrorHandler

                                { error check: bad payload checksums (count in upper word of typeAndBadF16) }
                                test        flagsAndBadF16, kUpperWordMask  wz
                        if_nz   mov         _x, #cBadPayloadChecksum
                        if_nz   jmp         #ErrorHandler

                                { check command type }
                                test        flagsAndBadF16, #cCommandTypeFlag   wc  'c=1 user command

                                { if user command do port lookup elsewhere }
                        if_c    jmp         #UserPortLookup

                                { admin command }


    {todo: reduce permanent code by making everything except ping and stayAwake handled by paged code }

                                cmp         port_SH, #0                     wz      'standard admin commands from Crow specification
                        if_z    jmp         #StandardAdmin
    
                                cmp         port_SH, propCrowAdminPort      wz      'PropCrow admin commands
                        if_z    mov         _page, #cPropCrowAdmin
                        if_z    jmp         #ExecutePage

                                { admin port is closed }
                                mov         _x, #cPortNotOpen
                                jmp         #ErrorHandler 


{ UserPortLookup
    Called when a user command has arrived. The 
}
UserPortLookup
                                mov         _page, #cUserCommand
                                jmp         #ExecutePage

kUpperWordMask long $ffff_0000



{ UniversalAdmin
    The universal admin commands (admin port 0) are defined in "Crow Specification v1.txt". There are
  two commands: ping and getDeviceInfo. ping will be taken care of in permanent code, while getDeviceInfo
  is done with paged code.
}
'UniversalAdmin
'                                { universal admin command with no payload is ping }
'                                cmp         payloadSize, #0                 wz      'z=1 ping command
'                        if_nz   jmp         #:getDeviceInfo
'                                jmp         #SendFinalResponse                      'send ping response (payloadSize==0), then go to ReceiveCommand
'
'                                { only other universal admin command, getDeviceInfo, has 0x00 as payload }
':getDeviceInfo                  cmp         payloadSize, #1                 wz      'z=1 correct payload size
'                        if_z    rdbyte      cnt, rxBufferAddr               wz      'z=1 correct payload byte
'                        if_nz   jmp         #ReceiveCommand                         '...command not getDeviceInfo or ping
'                                mov         _page, #cGetDeviceInfo                  'perform getDeviceInfo
'                                jmp         #ExecutePage


{ StandardAdmin
    This is the first level handler for admin commands defined by the Crow standards. The commands ping
  and echo use permanent code, the other commands use paged code.
}
StandardAdmin
                                { ping() }
                                cmp         payloadSize, #0                 wz
                        if_z    jmp         #SendFinalResponse
                        
                                { for all other commands, first byte is command code }
                                rdbyte      _x, rxBufferAddr                wz

                                { getDeviceInfo(), code = 0x00 } 
                        if_nz   jmp         #:checkIfEcho
                                cmp         payloadSize, #1                 wz      'z=0 payload size incorrect (require exactly one byte)
                                test        flagsAndBadF16, isOpenFlag      wc      'c=0 no open transaction
                    if_nc_or_nz jmp         #ReceiveCommand
                                mov         _page, #cGetDeviceInfo
                                jmp         #ExecutePage

:checkIfEcho                    cmp         _x, #1                          wz
                        if_nz   mov         _page, #cOtherStandardAdmin             'all other standard admin commands taken care of with paged code
                        if_nz   jmp         #ExecutePage
                                
                                { echo(numIntermediates=0, bytes=[]), code = 0x01 }

                                cmp         payloadSize, #2                 wc      'c=1 payload size too small (require 2+ bytes)
                                test        flagsAndBadF16, isOpenFlag      wz      'z=1 no open transaction (command was muted)
                    if_c_or_z   jmp         #ReceiveCommand

                                { todo: consider revising echo -- limit on num intermediates; also exact echo (incl. init 2 bytes) }

                                mov         _y, rxBufferAddr
                                add         _y, #1
                                rdbyte      _x, _y                          wz      '_x = number of intermediate responses is second byte
                                add         _y, #1                                  '_y = address of bytes to echo (starting at third byte, if provided)
                                mov         _z, payloadSize
                                sub         _z, #2                                  '_z = number of bytes to echo

                        if_z    jmp         #:finalEcho

:intermediateEcho               mov         _addr, _y
                                mov         _count, _z
                                call        #SendIntermediate
                                djnz        _x, #:intermediateEcho

:finalEcho                      mov         _addr, _y
                                mov         _count, _z
                                jmp        #SendFinalResponse



{ LockSharedAccess
  A call to LockSharedAcccess must be followed by a call to UnlockSharedAccess.
}
'LockSharedAccess
                                'or      outa, pin27
'LockSharedAccess_ret            ret

{ UnlockSharedAccess
}
'UnlockSharedAccess
                                'andn    outa, pin27
'UnlockSharedAccess_ret          ret



{ TxSendBytes
    Internal routine used to send bytes. It also updates the running F16 checksum. It assumes
  the tx pin is already an output. Bytes are sent from the hub.
    This routine should not be called by user code -- use the complete or partial sending routines.
    The lowest bitPeriod supported by this routine is 32 or 33 clocks (32 clocks requires that
  the stopBitPeriod be a multiple of 2 to avoid worst case timing for hub reads).
    Before: _txAddr = address of hub bytes to send
            _txCount = number of bytes to send; IMPORTANT: must not be zero
    After:  _txAddr = address immediately after last byte sent
            _txCount = 0
    Guarantee: z flag not modified
}
TxSendBytes
                                { First, check if there is no open transaction and abort if that is the case. Although the
                                    line should be released in that case (the tx pin not an output) this check is still an
                                    important safety measure. It also shortens the amount of time before waiting for a command.
                                  Ideally, code should not be calling the sending routines if there's no open transaction, but
                                    it may not always be practical to avoid that. }
                                test        flagsAndBadF16, isOpenFlag      wc      'c=0 transaction not open
                        if_nc   jmp         TxSendBytes_ret                         '...abort for no open transaction

                                rdbyte      _txByte, _txAddr
                                
                                mov         _txWait_SH, cnt
                                add         _txWait_SH, #9

:byteLoop                       waitcnt     _txWait_SH, txBitPeriodA                'start bit
                                andn        outa, txMask

                                add         _txF16L, _txByte                        'do F16 calculation
                                cmpsub      _txF16L, #255
                                add         _txF16U, _txF16L
                                cmpsub      _txF16U, #255

                                shr         _txByte, #1                     wc
                                waitcnt     _txWait_SH, txBitPeriodB                'bit0
                                muxc        outa, txMask

                                mov         _txTmp_SH, #6
                                add         _txAddr, #1

:bitLoop                        shr         _txByte, #1                     wc
:twiddle                        waitcnt     _txWait_SH, txBitPeriodA                'bits1-6
                                muxc        outa, txMask
                                xor         :twiddle, #1
                                djnz        _txTmp_SH, #:bitLoop
            
                                shr         _txByte, #1                     wc
                                
                                waitcnt     _txWait_SH, txBitPeriodA                'bit7
                                muxc        outa, txMask

                                rdbyte      _txNextByte, _txAddr

                                waitcnt     _txWait_SH, stopBitDuration             'stop bit
                                or          outa, txMask

                                mov         _txByte, _txNextByte

                                djnz        _txCount, #:byteLoop

                                waitcnt     _txWait_SH, #0                          'ensure line is high for a full stop bit duration

TxSendBytes_ret                 ret 


{ TxSendAndResetF16
    Helper routine to send the current F16 checksum (upper first, then lower). It 
  also resets the checksum after sending.
}
TxSendAndResetF16
                                { save F16 to hub }
                                mov         _txAddr, txScratchAddr
                                wrbyte      _txF16U, _txAddr
                                add         _txAddr, #1
                                mov         _txCount, #2
                                wrbyte      _txF16L, _txAddr
                            
                                { send F16 }
                                mov         _txAddr, txScratchAddr
                                call        #TxSendBytes

                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

TxSendAndResetF16_ret           ret




{ SendFinalHeader, SendIntermediateHeader (Partial Sending Routines)
    The partial sending routines exist to allow sending payload bytes from multiple random
  locations of hub RAM without buffering them first. If sending from a single contiguous block
  of hub RAM then it is easier to use the complete sending routines.
    Argument/Results:
        Before: _count = total payload size
        After:  _count is unchanged (unless it exceeds packet max of 2047)
    Usage:  mov     _count, <number of bytes total in payload>
            call    #SendFinalHeader
      <or>  call    #SendIntermediateHeader
      <then, if there is a payload -- repeat until all bytes sent>
            mov     _count, <number of bytes in payload fragment>
            mov     _addr, <address of payload fragment>
            call    #SendPayloadBytes
      <finally>
            call    #FinishSending
}
SendFinalHeader                 movs        _SendApplyTemplate, #$90                'Note: ReportCrowError assumes s-field of SendFinalHeader is RH0 template
                                jmp         #_SendEnforceSizeLimit

SendIntermediateHeader          movs        _SendApplyTemplate, #$80

_SendEnforceSizeLimit           max         _count, kCrowPayloadLimit
                                
                                { Compose header bytes RH0-RH2. RH2 (token) is constant for every response of this
                                    transaction and so it could be set once in ReceiveCommandFinish, but doing it here 
                                    saves one or two registers of permanent code. }
                                mov         _txTmp_SH, _count                       '_txTmp will be RH0
                                shr         _txTmp_SH, #8                           'this requires _count does not exceed limit
_SendApplyTemplate              or          _txTmp_SH, #0-0
                                mov         _txAddr, txScratchAddr                      
                                wrbyte      _txTmp_SH, _txAddr                      'RH0
                                add         _txAddr, #1
                                wrbyte      _count, _txAddr                         'RH1
                                add         _txAddr, #1
                                wrbyte      token_SH, _txAddr                       'RH2


                                { reset F16 }
                                mov         _txF16L, #0
                                mov         _txF16U, #0

                                { send RH0-RH2 }
                                mov         _txAddr, txHeaderAddr
                                mov         _txCount, #3
                                call        #TxSendBytes

                                { send RH3-RH4 (the header F16) }
                                call        #TxSendAndResetF16

                                { Prepare for first payload chunk. Chunking requires inserting an F16 checksum into the byte stream after
                                    every 128 bytes of payload data, and also after any remainder bytes at the end (when the payload size
                                    is not a multiple of 128). This is accomplished using a variable and a flag:
                                        rspChunkRemaining - This is reset to 128 at the start of each new chunk. It is decremented
                                                             as payload bytes are sent. When it reaches zero the F16 bytes are sent
                                                             and the process starts over with a new chunk.
                                        sendF16 flag in flagsAndBadF16 - This flag is set when payload bytes have been sent and
                                                             is cleared immediately after F16 bytes have been sent. If it is set when
                                                             FinishSending is called it means the F16 bytes for the last chunk still
                                                             need to be sent (i.e. it was a partial chunk).
                                  So, we need to set rspChunkRemaining to 128. The sendF16 is automatically cleared for the first
                                    response, but we still need to clear it for later responses when intermediates are used.   
                                }
                                mov         rspChunkRemaining, #128             'number of payload bytes remaining in the current chunk before F16 bytes
                                andn        flagsAndBadF16, #cSendF16Flag       'don't send F16 unless payload bytes sent
SendHeader_ret
SendFinalHeader_ret
SendIntermediateHeader_ret      ret
    

{ SendPayloadBytes (Partial Sending Routine)
    This routine sends payload bytes for a response packet that has been started with a
  call to SendFinalHeader or SendIntermediateHeader. It automatically inserts F16 checksums
  into the byte stream at the end of every full chunk. (The F16 for a partial last chunk is
  sent by FinishSending.)
    Note that the total number of bytes to send must still be known before sending the header.
  The total sum of bytes sent using one or more SendPayloadBytes calls must exactly match the
  payload size passed to the header sending routine -- if it does not, then the Crow host (i.e. PC)
  will experience some sort of error (e.g. timeout, unexpected number of bytes, bad checksum).
    Arguments/Results
        Before: _addr = starting address of payload bytes to send
                _count = number of bytes to send
        After:  _addr = address immediately after last byte sent
                _count = 0
    Usage:  mov     _count, <number of bytes to send with this call, may be zero>
            mov     _addr, <base address of bytes to send>
            call    #SendPayloadBytes
}
SendPayloadBytes
                                mov         _txCount, _count                wz
                        if_z    jmp         SendPayloadBytes_ret                    '...exit: nothing to send
                                max         _txCount, rspChunkRemaining
                                sub         _count, _txCount
                                sub         rspChunkRemaining, _txCount     wz

                                mov         _txAddr, _addr

                                call        #TxSendBytes                            'guaranteed to not to modify z flag

                                or          flagsAndBadF16, #cSendF16Flag           'payload bytes sent, so F16 must follow eventually

                                mov         _addr, _txAddr

                        if_nz   jmp         SendPayloadBytes_ret                    '...exit before sending F16

                                { chunk is finished, but there may be more payload bytes to send, so send checksum now }
                                call        #TxSendAndResetF16

                                { prep for next chunk - see notes in Send*Header }
                                mov         rspChunkRemaining, #128
                                andn        flagsAndBadF16, #cSendF16Flag           'checksums just sent, so clear flag
 
                                jmp         #SendPayloadBytes 

SendPayloadBytes_ret            ret


{ FinishSending (Partial Sending Routine)
    This routine finishes the response packet by sending final F16 payload checksums, if necessary.
}
FinishSending
                                test        flagsAndBadF16, #cSendF16Flag   wc
                        if_c    call        #TxSendAndResetF16
FinishSending_ret               ret


{ SendIntermediateResponse (Complete Sending Routine)
    This is a convenience routine for sending an intermediate response.
    Arguments/Results:
        Before: _addr = starting payload address
                _count = payload size                
        After:  _addr = address immediately after last byte sent
                _count = 0
}
SendIntermediate                call        #SendIntermediateHeader
                                call        #SendPayloadBytes
                                call        #FinishSending
SendIntermediate_ret            ret


{ SendFinalResponse, SendFinalAndReturn (Complete Sending Routines)
    These are convenience routines for sending a final response. They differ in what happens
  afterwards: either returning to the calling code, or immediately jumping to ReceiveCommand.
    Usage: set payloadSize and payloadAddr
            call    #SendFinalAndReturn
            -or-
            jmp     #SendFinalResponse
}
SendFinalResponse               movs        SendFinalAndReturn_ret, #ReceiveCommand
SendFinalAndReturn              call        #SendFinalHeader
                                call        #SendPayloadBytes
                                call        #FinishSending
                                call        #CloseTransaction
SendFinalAndReturn_ret          ret



{ RX Mixed Notes
    The _rxMixed register contains several pieces of information used by the receiving code:
        byteCount (bits 0-12) - the number of packet bytes received, as a negative number (used by cont-recal code)
        writeVetoes (bits 13-15) - flags for determining when to write the previously received byte to the payload
          buffer. Any one of them being set prevents the write (and _rxAddr increment) from occurring. After parser
          reset these flags must be set/cleared by shifted parsing code, so the code is making a decision about the
          current byte being written during the next receive loop. The flags:
            N: nonPayload   - bit 13 - set if the byte is a non-payload byte, cleared otherwise; set on reset
            L: driverLocked - bit 14 - set if the driver is locked; cleared on reset
            B: tooBig - bit 15 - set if command payload exceeds buffer capacity; cleared on reset
        lowBitCount (upper word) - the count of low data bits, used by the continuous recalibration code
    So this is the layout
        |---lowBitCount--|BLN|--byteCount--|
    Value after reset:
        |0000000000000000|001|1111111111111|
    Considerations:
        - The sizes of lowBitCount and byteCount were chosen so that this mechanism will work with payload sizes
            up to 4095 bytes (the expected maximum allowed in any future Crow revisions).
        - The byte count is made by the djnz at the bottom of the loop -- a jump is required anyway, so the byte
            count comes for free. _rxMixed never reaches zero since the initial value exceeds any possible
            packet size (the shifted parsing code enforces this limit, even if the host keeps sending bytes).
    See page 114.
}   
rxMixedReset            long    $3fff       'byteCount = -1, nonPayloadFlag = 1, all else clear/zero
'nonPayloadFlag, driverLockedFlag, tooBigFlag, and writeVetoesMask are located in shifted parsing code as spacer nops


lowCounterMode          long    $3000_0000

cmdBufferMaxSize      long cCmdBufferMaxSize

{ ExecutePage
    The code for PropCrow exceeds the cog's space, so a paging mechanism must be used. This paging mechanism
  also makes it easier to expand the base PropCrow implementation.
    Rules:
      - Code execution starts at the first register of the page.
      - Pages aren't reloaded if avoidable (so the code must reset itself if it self-modifies).
      - Pages aren't cached back to the hub (so they can't store information).
      - The page table is considered static (unlike the user ports table), so it is not protected by a hardware lock.
    Arguments/Results
        Before: _page = index in page table of page to execute
    Usage:  mov     _page, #<page index>
            call    #ExecutePage
    Note: _page (and ExecutePage's local variables) do not alias the Arguments/Results group of variables (e.g. _x).
  This allows using those registers to pass information to the loaded page. 
}
ExecutePage
:currPage                       cmp         _page, #cInvalidPage            wz      'curr page index stored in s-field (initially set to cInvalidPage)
                        if_z    jmp         #cPage                                  'if page already loaded then go

                                movs        :currPage, _page                        'update the current page (will repurpose _page later)

                                movd        :load, #cPage

                                shl         _page, #2                               '@(PageTable[i]) = @PageTable + 4*i
                                add         _page, pageTableAddr
                                rdword      _pageAddr, _page                        '_pageAddr is address of page
                                add         _page, #3
                                rdbyte      _pageTmp_SH, _page                      '_pageTmp is page size in longs
 
:load                           rdlong      0-0, _page
                                add         :load, kOneInDField
                                add         _page, #4
                                djnz        _pageTmp_SH, #:load

                                jmp         #cPage


{ CloseTransaction
    Used to close the transaction, preventing any more transmissions until the next command.
  Redundant calls are safe.
    Arguments/Results: none
    Usage:  call    #CloseTransaction
}
CloseTransaction                andn        flagsAndBadF16, isOpenFlag              'clear isOpen flag
                                andn        dira, txMask                            'release the line (make tx pin high-z)
CloseTransaction_ret            ret


{ ErrorHandler (jmp)
    Use this routine to process low-level errors -- errors that will be reported to the host using a 
  Crow error response. This routine determines whether the error should be reported, and then calls the
  sending code if necessary. In any case execution eventually goes to ReceiveCommand. 
    Arguments/Results
        Before: _x = error code, (optional: _y = data for some custom errors)
}
ErrorHandler
                                test        otherOptions, #cSendErrorFlag   wc  'c=0 error responses disabled
                                test        flagsAndBadF16, isOpenFlag      wz  'z=1 no open transaction
                   if_nc_or_z   jmp         #ReceiveCommand 

                                mov         _page, #cSendError
                                jmp         #ExecutePage


{ CopyString, CopyStringFromTable (both call)
    These routines are for copying NUL-terminated strings from one location in hub RAM to another.
  The CopyStringFromTable routine is for copying implementation defined strings that are in
  the StringTable (which is in the DatConstants block).

  CopyString
    This routine copies a NUL-terminated string up to a given maximum size (not including the NUL).
  There must be at least _copyMaxSize+1 free bytes starting at _copyDestAddr since this routine will
  always write a NUL, regardless if it copies one or not.
    Before: _copySrcAddr = address of NUL-terminated string to copy
            _copyDestAddr = address to copy string to (it always writes a NUL at end)
            _copyMaxSize = maximum size of string to copy, not including NUL
    After:  _copySrcAddr = address immediately after last byte copied (which may not have been a NUL)
            _copyDestAddr = address immediately after NUL
            _copySize = the size of the string copied, not including the NUL which was written
            _copyMaxSize unchanged
            z-flag = 1: _copySrcAddr-1 is NUL, 0: _copySrcAddr-1 is not NUL

  CopyStringFromTable
    For this routine the string to copy is identified by its index in the table. The routine then loads
  the address and proceeds as with CopyString (all strings in StringTable should be NUL-terminated).
    Before: _copyIndex = the index of the string in StringTable (in the DatConstants block)
            _copyMaxSize = maximum size of string to copy, not including NUL
            _copyDestAddr = the address to copy the string to (a NUL is always written at end)
    After:  same as for CopyString
}
CopyStringFromTable
                                shl         _copyIndex, #2                              '@(StringTable[i]) = @StringTable + 4*i
                                add         _copyIndex, deviceInfoAddr
                                add         _copyIndex, #(StringTable-DatConstants)
                                rdword      _copySrcAddr, _copyIndex
CopyString
                                mov         _copyTmp_SH, _copyMaxSize
                                mov         _copySize, #0

:loop                           rdbyte      _copyByte, _copySrcAddr             wz
                                add         _copySrcAddr, #1
                                wrbyte      _copyByte, _copyDestAddr
                                add         _copyDestAddr, #1
                        if_z    jmp         CopyString_ret                              'copied NUL, so all done
                                add         _copySize, #1
                                djnz        _copyTmp_SH, #:loop

                                { Didn't copy NUL, need to write one manually. }
                                wrbyte      kOneInDField, _copyDestAddr                 'kOneInDField has bottom byte zero
                                add         _copyDestAddr, #1

CopyStringFromTable_ret
CopyString_ret                  ret
                                



{ CopyBytes (call)
    Before: _copySrcAddr = address of bytes to copy
            _copyDestAddr = address to copy to
            _copyCount = number of bytes to copy
    After:  _copySrcAddr = address immediately after last byte copied from
            _copyDestAddr = address immediately after last byte copied to
            _copyCount = 0
}
CopyBytes
:loop                           rdbyte      _copyByte, _copySrcAddr
                                add         _copySrcAddr, #1
                                wrbyte      _copyByte, _copyDestAddr
                                add         _copyDestAddr, #1
                                djnz        _copyCount, #:loop
CopyBytes_ret                   ret






pin27 long |< 27

'pause long 8_000_000
total long 0




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
'                                rdbyte      _x, _addr      
'                                mov         txMask, #1
'                                shl         txMask, _x
'                                or          outa, txMask
                               
                                add         _addr, #1                           'rxBufferAddr, cmdBufferResetAddr
                                rdword      rxBufferAddr, _addr 
                                mov         cmdBufferResetAddr, rxBufferAddr    'cmdBufferResetAddr = cmdBufferAddr - 1 due to pre-increment for writes
                                sub         cmdBufferResetAddr, #1

                                add         _addr, #2                           'txBufferAddr
                                rdword      txBufferAddr, _addr

                                add         _addr, #2                           'maxRxPayloadSize
                                'rdword      maxRxPayloadSize, _addr

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

                                add         _addr, #4
                                mov         driverLockAddr, _addr               'driverLockAddr

                                { todo: reorder }
                                mov         _addr, par
                                add         _addr, #25
                                rdbyte      otherOptions, _addr

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

{ ---- }

'payloadAddr     res

{ Paging Temporaries
    These registers will be undefined after every call to ExecutePage, so alias them with care.
}

_page           res
_pageAddr       res

{ ---- }

_rcvyCurrPhsb
_rxLastWait1
_txMaxChunkRemaining    res

_copyIndex
_calcOptions
_rxAddr

_copySize
_rcvyPrevPhsb
_txAddr         res

'_utilCount
_copyMaxSize
_calcClk
_rxCountdown
_txCount        res

_copyCount
_calcBaud
_rxMixed  
_txNextByte     res

_copyDestAddr
_rxLockingUser
'_utilFlags
_calcIBTimeout
_txByte         res

'_utilY
_copySrcAddr
_calcBreak
_txF16L
_rxPrevByte         res

'_utilX
_copyByte
_calcTwoBit
_txF16U
_rxRemaining        res









{ Semi-Global Variables }

rspChunkRemaining
cmdLowBits       res

cmdLowClocks     res

payloadSize     res

{ ---- }


{ Serial Timings }
'rxBitPeriodA    res
'rxBitPeriodB    res
'rxBitPeriod5    res

rxMask  res
txMask  res

bitPeriod0      res
bitPeriod1      res
startBitWait    res
stopBitDuration res
breakMultiple   res
recoveryTime    res
ibTimeout       res
rxPhsbReset     res

otherOptions    res

{ Constants (after initialization) }
deviceInfoAddr          res
accessLockID            res
rxBufferAddr            res
cmdBufferResetAddr      res
txBufferAddr            res
numUserPortsAddr        res
maxUserPorts            res
userPortsAddr           res

'maxRxPayloadSize        res
txScratchAddr           res
driverLockAddr          res

serSettingsChangedAddr  res
pageTableAddr           res



{ Argument/Result Variables
    The following registers are never used by the sending or utility routines except as calling arguments
  or return results, in which case that use is clearly stated.
    These registers are used by the receiving code (_rx), which means they will be undefined immediately
  after a command is received, but their values will be stable and predictable after that.
}
fit 489 'On error: too many res variables. Reduce variables, cPage, or cPageMaxSize.
org 489

_x
_rxOffset       res

_y 
_rxResetOffset  res

_z
_rxWait0        res

_addr
_rxWait1        res

_count 
_rxF16L         res


{ Fixed Location Globals
    The transmit loop uses a bit twiddling mechanism to toggle between the two bit periods. This requires
  that txBitPeriodA be at an even address, and txBitPeriodB immediately follow it.
}
fit 494
org 494

txBitPeriodA    res 'must be at even address
txBitPeriodB    res 'must be at address immediately after txBitPeriodA



