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
    These settings determine the sizes of the reserved buffers.
    PropCrow has two dedicated buffers for command and response payloads (cmdBuff and rspBuff).
  These buffers may actually be identical (overlap) to save space, but doing this would make
  simultaneously parsing a command and composing a response more difficult (only user code
  would need to worry about this -- the driver code would be OK).
    By specification, Crow payloads (both kinds) may not exceed 2047 bytes, so the buffers do not
  need to be larger than this.
    The minimum command buffer size is two bytes due to the mechanism used to prevent overruns.
    The minimum response buffer size is 200 bytes since the driver uses the response buffer to
  compose error messages.

todo: buffer size checks on error messages

 It assumes (without checking) that it has at least this many bytes
  bret
    The command payload buffer must be at least two bytes due to the mechanism used to prevent
  buffer overruns.
    The driver uses the response buffer for composing low-level error messages, so it must
  be at least 256 bytes (the driver does not     The command and response buffers may be the same to conserve space. However, doing this
  would make parsing a command and composing a response more difficult (only user code would
  need to worry about this, the driver .

do not have to come from the response buffer.

}
cCmdBuffSizeInLongs     = 100
cRspBuffSizeInLongs     = 80

cCmdBuffSize    = 4*cCmdBuffSizeInLongs
cRspBuffSize    = 4*cRspBuffSizeInLongs
cMaxNumUserPorts    = 10    'May be any two-byte value (as memory allows).

cUserPortsLongs  = ((cMaxNumUserPorts*6) / 4) + 1


{ Abort Codes }
cFailedToObtainLock     = -1000

{ Driver States }
cPreLaunch              = 0
cInitializing           = 1
cIdleWithBD             = 2
cIdleNoBD               = 3



{ Other Constants }
cPropCrowID     = $abcd     'must be two byte value


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

{ ...for clockOptions }





{ Paging Constants 
    Paging is used to increase code space. This is the layout of cog registers:

        From          | To (inclusive)    | Description
       ---------------|-------------------|------------------------------------
        0             | cPageBLimit-1     | Page B, also Entry initialization
        cPageBLimit   | cPageA-1          | Permanent
        cPageA        | cPageALimit-1     | Page A, also FinishInit (may start in Permanent)
        cPageALimit   | 495               | Res'd

    See the LoadPageB and ExecutePageA routines for more information.
    If you're reading this you might be getting FIT errors from the compiler. Here are
  some remedies for various situations:
    - Page too big
        Decrease page's code, or increase cPageAMaxSize or cPageBLimit.
    - Permanent code too big
        Decrease permanent code, decrease cPageBLimit, or increase cPageA.
    - FinishInit too big.
        Decrease FinishInit code (maybe move to Entry initialization area), decrease
        cPageBLimit, or increase cPageA or cPageAMaxSize.
    - Entry initialization too big.
        Decrease Entry initialization code (maybe move to FinishInit), or increase cPageBLimit.
    - Too many res'd variables.
        Decrease variables, or decrease cPageA or cPageAMaxSize.
}
cPageBLimit     = 35
cPageA          = 408
cPageAMaxSize   = 39
cPageALimit     = cPageA + cPageAMaxSize


{ Crow Error Codes
    These are the error codes assigned by the Crow standard.
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
    Translated to standard error codes in SendCustomError. These must be 32-63.
}
cDriverLocked           = 32


{ StringTable Entries }
cPropCrowStr        = 0
cWaitingForStr      = 1
cToFinishStr        = 2
cUnknownErrStr      = 3
cSpinStr            = 4
cDefaultUserName    = 5

{ Page Indices
    The "_A" or "_B" suffix clarifies what kind of page it is -- refer to Paging Constants.
}
cCalculateTimings   = 0
cGetDeviceInfo      = 1
cUserCommand        = 2
cPropCrowAdmin      = 3
cSendError          = 4
cBlinky             = 5
cSendEcho           = 6
cCalc2              = 7
cCalc3              = 8
cSendCustomError    = 9
cSendErrorFinish    = 10
cStandardAdminCont  = 11
cReceiveExtra_B     = 12
cFramingError_A     = 13
cBaudDetect_A       = 14
cNumPages           = 15
cInvalidPage        = 511   'signifies no valid page loaded


{ Special Purpose Register Usage
    Out of necessity PropCrow makes use of some special purpose registers for variables. 
    Variables aliased to shadow SPRs have a "_SH" suffix as a warning to use them only in the d-field.
    The counter A and video generator registers are never used by PropCrow -- they have been left
  available for custom code.
}

{ SPR Global Variables }

flagsAndBadF16  = $1F7      'dirb       see flagsAndBadF16 Notes
port_SH         = $1F0      'sh-par     not needed by implementation after invoking user code
cmdDetails      = $1F5      'outb       cmdDetails is CH3
token_SH        = $1F2      'sh-ina     must remain unchanged for sending responses

{ SPR Local Variables }

_txWait_SH      = $1F1      'sh-cnt
_rxF16U_SH      = $1F1      'sh-cnt

_idleWait_SH    = $1F3
_mathTmp_SH     = $1F3
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


pub new | __pause

    dira[26] := 1
    outa[26] := 1

    peekpoke.setParams(31, 30, 115200, 2)
    peekpoke.new

    word[30000] := @PageTable
    word[30002] := @Entry
    word[30004] := @ControlBlock

    repeat index from 0 to cNumPages-1
        word[@PageTable][2*index] += @@0

    repeat index from 0 to cNumStrings-1
        word[@StringTable][index] += @@0
    
    __cmdBuffAddr           := @CmdBuffer
    __rspBuffAddr           := @RspBuffer
    __userPortsTableAddr    := @UserPortsTable
    __pageTableAddr         := @PageTable
    __stringTableAddr       := @StringTable
    __txBlockAddr           := @TxBlock

    __numUserPorts      := 3
    __userPorts.word[0] := 0
    __userPorts.word[3] := 1
    __userPorts.word[6] := 78

'    if __lockID > 7
'        __lockID := locknew()
'        if __lockID > 7
'            abort cFailedToObtainLock


    result := cognew(@Entry, @DriverBlock)

    __pause := 120_000_000
    result := cnt

    word[15000] := string("Test Object")

    repeat
        __lockingUser := 0
        outa[26] := 1
        waitcnt(result += __pause)
        __lockingUser := 15000
        outa[26] := 0
        waitcnt(result += __pause)

dat

{ DriverBlock
    This is the primary data structure for setting up and interfacing with the driver cog.
  The address of DriverBlock is passed as the PAR parameter to the driver cog.
    The format of this structure is hardcoded into the driver's code. Changes here may require
  significant code rewrites (search for "Assumes DriverBlock Layout").
    Key for field type:
        I - Initialization value. Must be set before launch and remain constant after.
        D - Only driver cog writes these values.
        ID -
        L - Locked settings -- all cogs must use a hardware lock (memLockID) to read and write*. If other cogs
            change any of these settings they must raise changedFlag (write a non-zero byte) before releasing the lock.
            The driver cog will clear changedFlag (under lock) when it applies the settings.
        Lf - Any cog may read without hardware lock, but all cogs must have lock to write.
        U - Only driver cog may set to any value, only user object with same address may set to zero. All changes
            require hardware lock.
        s - Settings that may be read or written by any cog without obtaining hardware lock (if done atomically).
            Changes do not raise the changedFlag.
        - - reserved fields.
    The driver considers clkfreq (LONG[0]) and clkmode (BYTE[4]) to be L-settings. Cooperating code should
  change these only under hardware lock (memLockID), and should raise changedFlag before releasing the lock.
  If these are changed without raising the changedFlag and framing errors occur the driver will notice that the
  values have changed and will reload the settings (assuming those hub locations are updated).

*If user code just wants to know the value of setting at the given instant it can use an atomic read
without getting the lock. Correlating multiple fields (including the changed flag) requires a lock.

Framining Errors
- first check if settings have changed, including clkfreq and clkmode
- if so, reload settings
- if framing errors continue, eventually enter baud detect mode, if autobaud enabled


otherOptions
-------------
shutdownDriver          = %00_0000_0001      1 instructs driver to do graceful cog stop
enableDriver            = %00_0000_0010      0 puts driver in idle mode until setting changes
rxLevelInverted         = %00_0000_0100
txLevelInverted         = %00_0000_1000
interruptLevel          = %00_0nnn_0000
useTwoStopBits          = %00_1000_0000
enableErrorResponses    = %01_0000_0000
enableBreakDetection    = %10_0000_0000

interruptLevel:
    otherOptions & $70 =
        $00 - lowest - 1 clock
        $10 - low - 0.75 bit period
        $20 - medium - 10 bit periods
        $30 - high - 1/16th break
        else - off
At very low baudrates or short break thresholds the high level may be shorter than low or medium, but the defitions do not change.

clockOptions Bitfield
---------------------
in four identically formatted bytes for each of four clock sources
bytes: 0: xtal, 1: xin, 2: rcfast, 3: rcslow
for each clock source:
useSource           = %0_0001   if false, driver will be idle until setting or source changes
enableAutobaud      = %0_0010   enables autobaud features (baud detect, cont recal) if framing errors threshold is met or if commanded
requireBaudDetect   = %0_0100   ignored if enableAutobaud is false
requireContRecal    = %0_1000   ignored if enableAutobaud is false
writeClkfreq        = %1_0000   if autobaud is used the driver will write its best estimate of clkfreq to LONG[0] (assuming host provides a nominal baudrate)

breakThreshold notes
- the break threshold time must not exceed the cnt rollover time (e.g. 53s @ 80 MHz) -- this should not be a problem (remember, to disable, set to zero)
- this threshold is the minimum duration of a break condition before PropCrow will detect it. In practice, the actual break condition sent
  must be greater than this threshold to be reliably detected. todo: how must greater? 1/16th + margin?
- break thresholds less than 160ms may not work reliably at slowest clock speeds (todo: explain)
- connection between break threshold and recovery time
}


DriverBlock
                                                    '   pos len typ notes
'Runtime State

__changedFlag               byte 0                  '   0   1   Lf  non-zero value: values changed; bits indicate which ones; 0: settings loaded
__driverState               byte 0                  '   1   1   ID  launching code must set this to 0 before launching
__lockingUser               word 0                  '   2   2   U   0: driver unlocked: non-zero: address of locking user

'Current Settings

__currRxPin                 byte 31                 '   4   1   L
__currTxPin                 byte 30                 '   5   1   L
__currAddress               byte 1                  '   6   1   L   must be 1 to 31
                            byte 0                  '   7   1   -

__currBaudrate              long 115200             '   8   4   L   <300 becomes 300

__currClockOptions          long $1f1f_0b01         '   12  4   L

__currOtherOptions          word 0                  '   16  2   L
__currBreakThreshold        word 200                '   18  2   L   in MILLIseconds; 0 becomes 1 (set enableBreakDetection=0 to disable)

__currCommandPorch          long 16 | |< 31         '   20  4   L   in microseconds (bit 31 = 0) or bit periods (bit 31 = 1); 0 becomes 1

__currInterbyteTimeout      long 150_000            '   24  4   L   in microseconds (bit 31 = 0) or bit periods (bit 31 = 1)

__currMinResponseDelay      long 0                  '   28  4   L   in microseconds

__currPostResponseWait      long 0                  '   32  4   L   in microseconds

__currUserCodeTimeout       long 100_000            '   36  4   L   in microseconds (bit 31 = 0) or clocks (bit 31 = 1)

                            long 0                  '   40  4   -

'Reset Settings

long 0[10]

'Other Settings (Non-Resettable)

__breakHandler              word 0                  '   84  2   s   enableBreakDetection must be 1 even if defined; 0 selects driver's internal handler
                            word 0                  '   86  2   -

__remotePermissions         byte 0                  '   88  1   L
                            byte 0[3]               '   89  3   -

                            long                    '   92  4   -

'Initialization Constants

__memLockID                 byte 200                '   96  1   I
                            byte 0[3]               '   97  3   -

__cmdBuffAddr               word 0-0                '   100 2   I
__rspBuffAddr               word 0-0                '   102 2   I

__userPortsTableAddr        word 0-0                '   104 2   I
__pageTableAddr             word 0-0                '   106 2   I

__stringTableAddr           word 0-0                '   108 2   I
__txBlockAddr               word 0-0                '   110 2   I

__cmdBuffSize               word cCmdBuffSize       '   112 2   I
__rspBuffSize               word cRspBuffSize       '   114 2   I

__maxNumUserPorts           word cMaxNumUserPorts   '   116 2   I
__numPages                  byte cNumPages          '   118 1   I
__numStrings                byte cNumStrings        '   119 1   I

                            long 0                  '   120 4   -

'Informational Settings

__deviceNameAddr            word 0                  '   124 2   s   0 disables
__deviceDescAddr            word $ffff              '   126 2   s   0 disables, $ffff selects "Propeller P8X32A (cog X) running PropCrow vM.m."

'Internal and Diagnostic

__cogID                     byte 200                '   128 1   D   set by driver cog during initialization; 200 is pre-initial-launch flag value
                            byte 0[3]               '   129 3   -




{ PageTable
    Pages are blocks of code or constants loaded into the cog's registers at runtime.
    Refer to Paging Constants.
    This table is used for both kinds of pages (A and B).
    Format:
      pos  len  value
      0    2    address of page
      2    1    (not used)
      3    1    length of page
}    
PageTable

'0: CalculateTimings
word    @CalculateTimings
byte    0
byte    CalculateTimings_end - CalculateTimings + 1

'1: GetDeviceInfo
word    @GetDeviceInfo
byte    0
byte    GetDeviceInfo_end - GetDeviceInfo + 1

'2: UserCommand
word    @UserCommand
byte    0
byte    UserCommand_end - UserCommand + 1

'3: PropCrowAdmin
word    @PropCrowAdmin
byte    0
byte    PropCrowAdmin_end - PropCrowAdmin + 1

'4: SendError
word    @SendErrorPg
byte    0
byte    SendErrorPg_end - SendErrorPg + 1

'5: Blinky
word    @Blinky
byte    0
byte    Blinky_end - Blinky + 1

'6: SendEcho
word    @SendEcho
byte    0
byte    SendEcho_end - SendEcho + 1

'7: Calc2
word    @Calc2
byte    0
byte    Calc2_end - Calc2 + 1

'8: Calc3
word    @Calc3
byte    0
byte    Calc3_end - Calc3 + 1

'9: SendCustomError
word    @SendCustomError
byte    0
byte    SendCustomErrorPg_end - SendCustomErrorPg + 1

'10: SendErrorFinish
word    @SendErrorFinish
byte    0
byte    SendErrorFinishPg_end - SendErrorFinishPg + 1

'11: StandardAdminCont
word    @StandardAdminCont
byte    0
byte    StandardAdminCont_end - StandardAdminCont + 1

'12: ReceiveExtra_B
word    @ReceiveExtra_B
byte    0
byte    ReceiveExtra_B_end - ReceiveExtra_B + 1

'13: FramingError_A
word    @FramingError_A
byte    0
byte    FramingError_A_end - FramingError_A + 1

'14: BaudDetect_A
word    @BaudDetect_A
byte    0
byte    BaudDetect_A_end - BaudDetect_A + 1


{ UserPortsTable

    todo: implement

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


{ StringTable
    Each entry in the table is a word containing the address of a NUL-terminated 7-bit ascii string.
}
StringTable
word @PropCrowStr
word @WaitingForStr
word @ToFinishStr
word @UnknownErrStr
word @SpinStr
word @DefaultUserName   '5

{ Strings }
PropCrowStr         byte "PropCrow", 0
WaitingForStr       byte "Waiting for ", 0
ToFinishStr         byte " to finish.", 0
UnknownErrStr       byte "Unknown error.", 0
SpinStr             byte "Spin Object", 0
DefaultUserName     byte "User Object", 0
DefaultDeviceDesc   byte "Propeller P8X32A (cog ", 0
'DidNotRespondStr    byte " never responded.", 0
'WasUnresponsiveStr  byte " was unresponsive.", 0


{ TxBlock
    This block is used by the driver cog for various sending purposes. No other
  cog should modify this data.
}
TxBlock
long    0       'first long assumed to be txScratch

{ DeviceInfoTemplate, part of TxBlock 
    A template for sending getDeviceInfo responses. The mutable parts (for user ports) are
  sent separately.
}
DeviceInfoTemplate
long    $0000_0200 | ((cPropCrowID & $ff) << 24) | ((cPropCrowID & $ff00) << 8)             'Crow v2, implementationID = cPropCrowID
long    $FF02_0000 | ((cCmdBufferMaxSize & $ff) << 8) | ((cCmdBufferMaxSize & $700) >> 8)   'max commmand payload size, 2 admin ports (top byte not sent from here) 
long    $0000_0000 | ((cPropCrowID & $ff) << 24) | ((cPropCrowID & $ff00) << 8)             'admin ports 0 and PropCrowID

{ ErrorResponseTemplate, part of TxBlock
    This template sets up an error response with no standard details, and one implementation provided
  ascii error message. After writing this template to the response buffer, all that remains is to set
  the first byte (type OR'd with 0x80), set byte 8 to message length (assuming it is less than 256),
  and write the message at byte 9 (terminating NUL not required).
} 
ErrorResponseTemplate
long    $0003_00FF      'bottom byte written later
long    $0009_0001      'top byte of message length is zero (assume all messages are less than 256 characters)





{ FramingError_A
    Handles framing errors.
}
org cPageA
FramingError_A
                            {todo: increment consecutive framing errors count
                                    if count reaches limit and baud detect enabled, go to baud detect
                                    otherwise, force reload the settings }
FramingError_A_end
                                jmp         #ReceiveCommand
fit cPageALimit 'On error: page too big.

{ BaudDetect_A
    Enters baud detection mode.
}
org cPageA
BaudDetect_A
BaudDetect_A_end                jmp         #ReceiveCommand
fit cPageALimit 'On error: page too big.

{ ReceiveExtra_B
    This page starts with a 16 register nibble table. This table contains the number of zero bits for the
  numbers 0 to 15. It is used by the continuous recalibration code -- the values are in the upper word since
  that's where zeroBitCount is located in _rxMixed.
}

org 0
ReceiveExtra_B
long    $0004_0000
long    $0003_0000
long    $0003_0000
long    $0002_0000
long    $0003_0000
long    $0002_0000
long    $0002_0000
long    $0001_0000
long    $0003_0000
long    $0002_0000
long    $0002_0000
long    $0001_0000
long    $0002_0000
long    $0001_0000
long    $0001_0000
long    $0000_0000


ParsingErrorHandler_B
                       
                            {todo: check if settings have changed, if so then reload
                                    otherwise, go to recovery mode }
 
{ RecoveryMode
  When framing or parsing errors occur the implementation enters recovery mode. In this mode the implementation
    waits for the rx line to be in high-idle for a certain period of time before attempting to receive another
    command. If the line is low for long enough then the implementation determines that a break condition has occurred.
  See page 99.
}
'todo (3/17): does the removal of the ctrb off code change any timings? (3/28: don't think so)
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

                                mov         _page, #cBlinky
                                jmp         #ExecutePageA

ReceiveExtra_B_end              long 0

fit cPageBLimit 'On error: page too big. Refer to Paging Constants.

{
JumpTest
                                mov         inb, #12
                                mov         cnt, cnt
                                add         cnt, fourMill
:loop                           xor         outa, pin27
                                waitcnt     cnt, fourMill
                                jmp         #:loop
fourMill                      
}

{ SendEcho (page)
    This page is invoked by AdminCommandStart for sending an echo response.
    It is assumed that the command was valid and that a response is expected.
}
org cPageA
SendEcho
                                { The command is echo(numIntermediates=0, filler=[]).
                                  There is a mandatory second byte in echo commands for the number of intermediate responses
                                    to send. Only the bottom 3 bits are used, the rest are ignored (so a limit of 7 intermediates).
                                  Any additional bytes past the second byte are optional filler. They have no meaning to the device
                                    and their values are ignored. For echo commands they are sent back verbatim to the host. }

                                { Get number of intermediate responses in _y. }
                                mov         _addr, rxBufferAddr
                                add         _addr, #1
                                rdbyte      _y, _addr
                                and         _y, #%111                       wz

                                { Echo responses sent directly from the command payload buffer. }

                        if_z    jmp         #:finalEcho

:intermediateEcho               mov         _addr, rxBufferAddr
                                mov         _count, payloadSize
                                call        #SendIntermediate
                                djnz        _x, #:intermediateEcho

:finalEcho                      mov         _addr, rxBufferAddr
                                mov         _count, payloadSize
SendEcho_end                    jmp        #SendFinalResponse
fit cPageALimit 'On error: page is too big. Reduce code or increase cPageSize.


{ Blinky
mov     _page, #cBlinky
jmp     #ExecutePageA
}
org cPageA
Blinky  
'                                call        #Trace
'
'                                mov         cnt, cnt
'                                add         cnt, pause
'                                xor         outa, pin27
'                                waitcnt     cnt, pause
'                                jmp         #$-2

                                mov         inb, #12
                                mov         cnt, cnt
                                add         cnt, Blinky_end
:loop                           xor         outa, pin27
                                waitcnt     cnt, Blinky_end
'                                djnz        inb, #:loop
                                jmp         #:loop
'                                jmp         #RecoveryMode
Blinky_end                      long 4_000_000
fit cPageALimit


{ StandardAdminCont
    Invoked by StandardAdminStart, this page continues the work of processing a standard admin command.
  At this point we know the command is not ping, echo, or hostPresence.
    Assumes:    _x = command type (first command payload byte)
}
org cPageA
StandardAdminCont
                                cmp         _x, #0                          wz
                        if_nz   jmp         #:checkNext
                                
                                { getDeviceInfo(), type = 0x00 } 
                                cmp         payloadSize, #1                 wz      'z=0 payload size incorrect (require exactly one byte)
                                test        flagsAndBadF16, isOpenFlag      wc      'c=0 no open transaction
                    if_nc_or_nz jmp         #ReceiveCommand
                                mov         _page, #cGetDeviceInfo
                                jmp         #ExecutePageA
:checkNext
StandardAdminCont_end           jmp         #ReceiveCommand
fit cPageALimit 'On error: page is too big. Reduce code or increase cPageSize.


{ PgSendErrorResponse
    This page starts the process of sending a Crow-level error response (not an upper-level protocol error response).
  Crow-level error responses indicate some problem that prevents an otherwise valid command from being responded to normally.
  Error responses are sent only for 'reportable' errors -- some errors have to be silently ignored (e.g. bad
  reserved bits in the command header, or errors for any command with muted responses). See the Crow v2
  specification for more details.
    To report an error: set _x to the error number, then jump to ErrorHandler. That routine will determine whether
  the error response should be sent, in which case it will execute this page.
    Some errors require _y to be set as well. See SendCustomError.
}
org cPageA
SendErrorPg
                                { It is assumed that _x has been set to a standard error number (< 32) or a custom error number (32-63).
                                  If _x is a standard error number then the error response will include no implementation
                                    specific error details (i.e. no ascii message).
                                  Custom errors will include an ascii error message, and the custom error number will
                                    be translated to a standard error number.
                                  Custom errors may require _y be set to some value. }

                                { The entire payload will be composed in the response buffer and sent on the SendErrorFinish page.
                                    When executed, that page expects _x is E0, and _count is the size of the response payload. }

                                { Is the error number a standard error number? Custom errors on separate page. }
                                cmp         _x, #31                     wc
                        if_nc   mov         _page, #cSendCustomError
                        if_nc   jmp         #ExecutePageA

                                { If a standard error number was passed (_x < 32) we will not include any implementation
                                    specific details. This means E1 and E2 are undefined and can have any values. }
                                mov         _copyDestAddr, txBufferAddr
                                add         _copyDestAddr, #3                   '_copyDestAddr points to start of any standard details 

                                { If no standard details are included we will send a minimal response payload. }
                                mov         _count, #1

                                { PayloadTooBig sends the supported max size (two bytes) as a standard detail. }
                                cmp         _x, #cPayloadTooBig         wz
                        if_z    or          _x, #%0100_0000                     'standard details are included
                        if_z    add         _count, #4                          '+2 for E1-E2, +2 for details
                        if_z    mov         _copySrcAddr, txBlockAddr           'copy max size from device info template
                        if_z    add         _copySrcAddr, #4*(DeviceInfoTemplate - TxBlock + 1)
                        if_z    mov         _copyCount, #2
                        if_z    call        #CopyBytes

                                { PortNotOpen sends type (one byte: 0x00=admin, 0x01=user) and port number (2 bytes). }
                                cmp         _x, #cPortNotOpen                   wz
                        if_z    or          _x, #%0100_0000                         'standard details are included
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

                                mov         _page, #cSendErrorFinish
SendErrorPg_end                 jmp         #ExecutePageA
fit cPageALimit 'On error: page is too big. Reduce code or increase cPageSize.


{ SendCustomErrorPg
    Executed if _x is not a standard error number (< 32). Such numbers are used to indicate that an ascii 
  error message should be included, and the custom error number translated to a standard error number.
    Additional parameters expected:
            Driver Locked:      _y = user block address for user object with lock
}
org cPageA
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
                                mov         _copySrcAddr, txBlockAddr
                                add         _copySrcAddr, #4*(ErrorResponseTemplate - TxBlock)
                                mov         _copyCount, #8
                                call        #CopyBytes

                                { At this point _copyDestAddr points to byte 8 of buffer. Byte 8 will be written later, so advance
                                    _copyDestAddr to byte 9.
                                  At first _count will hold the message length, at :finish it will become the payload size. }
                                add         _copyDestAddr, #1

                                { _copyMaxSize applies to the CopyString* routines. It should be larger than any expected string
                                    fragment, but small enough that the message length can be guaranteed to be less than 256. }
                                mov         _copyMaxSize, #40

                                cmp         _x, #cDriverLocked          wz
                        if_nz   jmp         #:unknownCustom

:isLocked                       { Driver is locked. }
           
                                { Report as IsBusy. }
                                mov         _x, #cIsBusy 

                                { Message = "Waiting for <" + objectName + "> to finish." }

                                { "Waiting for <" }
                                mov         _copyIndex, #cWaitingForStr
                                call        #CopyStringFromTable
                                mov         _count, _copySize

                                { objectName address is first word of userObjectBlock (_y). If the address is NULL
                                    then the default string is used. }

                                rdword      _copySrcAddr, _y            wz
                        if_nz   jmp         #:nameNotNull

                                mov         _copyIndex, #cDefaultUserName       'use default name
                                call        #CopyStringFromTable
                                jmp         #:doneWithName

:nameNotNull                    call        #CopyString

:doneWithName                   add         _count, _copySize

                                { "> to finish." }
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
                                mov         _addr, txBufferAddr
                                add         _addr, #8
                                wrbyte      _count, _addr
            
                                { Make _count the payload length. }
                                add         _count, #9

                                { Set bit 7 (I flag) of E0 for implementation details. }
                                or          _x, #%1000_0000
                               
                                mov         _page, #cSendErrorFinish
SendCustomErrorPg_end           jmp         #ExecutePageA
fit cPageALimit 'On error: page is too big. Reduce code or increase cPageSize.


{ SendErrorFinishPg
    Executed at the very end of preparing an error response, when it is almost ready to be sent.
  Assumes _x = E0 and _count = response payload size.
}
org cPageA
SendErrorFinishPg
                                { Write first byte of response payload. }
                                mov         _addr, txBufferAddr
                                wrbyte      _x, _addr
                
                                { Both _count and _addr ready, so send. }
SendErrorFinishPg_end           jmp         #SendFinalResponse
fit cPageALimit 'On error: page is too big. Reduce code or increase cPageSize.


{ UserCommandPg
}
org cPageA
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
{
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
}
                                mov         _count, #16
                                mov         _addr, rxBufferAddr

UserCommand_end                 jmp         #SendFinalResponse
fit cPageALimit 'On error: page is too big. Reduce code or increase cPageSize.


org cPageA
PropCrowAdmin
                                mov         _addr, #0
                                mov         _count, #8
PropCrowAdmin_end               jmp         #SendFinalResponse
fit cPageALimit 'Page is too big. Reduce code or increase cPageSize.

org cPageA
GetDeviceInfo
                                'call        #LockSharedAccess


                                rdword      _x, numUserPortsAddr                    '_x = num open user ports to report
                                max         _x, #255                                'getDeviceInfo limited to reporting 255 user ports

                                mov         _count, _x                         'response payload size is 12 + 2*<num user ports> (assumes 2 admin protocols)
                                shl         _count, #1
                                add         _count, #12
                                call        #SendFinalHeader

                                mov         _addr, txBlockAddr
                                add         _addr, #4*(DeviceInfoTemplate - TxBlock)
                                mov         _count, #7
                                call        #SendPayloadBytes                       'send up to num reported user ports

                                wrbyte      _x, txBufferAddr
                                mov         _addr, txBufferAddr
                                mov         _count, #1
                                call        #SendPayloadBytes                       'send number of reported user ports

                                mov         _addr, txBlockAddr
                                add         _addr, #4*(DeviceInfoTemplate - TxBlock + 2)
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
fit cPageALimit 'On error: page is too big.

org cPageA

{ CalculateTimings
  This routine calculates the serial timings (in clocks) based on the settings stored in the hub.
}
CalculateTimings
                                'call        #LockSharedAccess

                                mov         _addr, par
                                rdlong      _loadBaud, _addr
                                add         _addr, #4
                                rdword      _loadIBTimeoutMS, _addr                 'in milliseconds
                                add         _addr, #2
                                rdword      _loadBreakMS, _addr                     'in milliseconds
                                add         _addr, #2
                                rdlong      _loadOptions, _addr
                                rdlong      _loadClkFreq, #0
                                rdbyte      _loadClkMode, #4

                                'call        #UnlockSharedAccess
                            
                                mov         _x, _loadClkFreq                    
                                shl         _x, #1
                                mov         _y, _loadBaud
                                call        #Divide
                                mov         _loadTwoBit, _y

                                mov         bitPeriod0, _loadTwoBit
                                shr         bitPeriod0, #1
                                min         bitPeriod0, #34                         'bitPeriod0 ready
                           
                                mov         txBitPeriodA, bitPeriod0
 
                                mov         bitPeriod1, bitPeriod0
                                test        _loadTwoBit, #1                     wc
                        if_c    add         bitPeriod1, #1                          'bitPeriod1 ready

                                mov         txBitPeriodB, bitPeriod1

                                'mov         rxBitPeriod5, bitPeriod0
                                'min         rxBitPeriod5, #33

                                mov         startBitWait, bitPeriod0
                                shr         startBitWait, #1
                                sub         startBitWait, #10                       'startBitWait ready; must not be < 5 (won't if bitPeriod0 >= 34)
            
                                mov         _page, #cCalc2
CalculateTimings_end
                                jmp         #ExecutePageA

fit cPageALimit 'On error: page is too big.


{ LoadSettingsStart_A

}
org cPageA
LoadSettingsStart_A
                                call        #RetainLock

                                { * Following Assumes DriverBlock Layout * }

                                { First, load clockOptions and otherOptions. }
                                mov         _addr, par
                                add         _addr, #12
                                rdlong      clockOptions, _addr                     'clockOptions
                                add         _addr, #4
                                rdbyte      otherOptions, _addr                     'otherOptions



                                { rx pin }
                                mov         _addr, par
                                add         _addr, #4
                                rdbyte      _x, _addr
                                mov         rxMask, #1
                                shl         rxMask, _x
                                movs        ctrb, _x                                'ctrb mode comes later (at rxLevelIsInverted)

                                { tx pin }
                                add         _addr, #1
                                rdbyte      _x, _addr
                                mov         txMask, #1
                                shl         txMask, _x                              'prepping outa comes later (at txLevelIsInverted)

                                { crow device address }
                                add         _addr, #1
                                rdbyte      _x, _addr
                                min         _x, #1
                                max         _x, #31
                                movs        _RxVerifyAddress, _x

                                { use baudrate and clkfreq (LONG[0]) }
                                add         _addr, #2
                                rdword      _loadBaud, _addr




LoadSettingsStart_A_end
fit cPageALimit 'On error: page is too big.


{ Idle_A
    This page MUST be executed only by LoadSettings (_idle* inherits/aliases some values from _load*).
    This page will change the reported driver status to IdleWithBD or IdleNoBD.
}
org cPageA
Idle_A
                                { The driver will enter idle mode for these reasons:
                                    (1) enableDriver=0, or
                                    (2) useSource=0 for clock source (clkmode), or
                                    (3) baudrate is too fast (depends on clkfreq and baudrate) and enableAutobaud=0.

                                  In each of these cases the decision to enter idle mode was made in LoadSettings. Note that 
                                    if enableAutobaud=1 the calculated baudrate being too fast will never cause the driver to enter
                                    idle mode. Instead, it will enter and stay in baud detect mode until it successfully determines
                                    the baud rate or the settings change.

                                  Exiting the Idle page (not necessarily idle mode) occurs when:
                                    (1) the changedFlag is raised, or
                                    (2) the clkfreq or clkmode values change (compared to those used last time in LoadSettings), or
                                    (3) a break was detected (requires enableBreakDetection, and depends on _idleBreakClocks and ctrb being setup).

                                  In cases 1 and 2 the page exits by executing the LoadSettingsStart page. In case 3 it exits by
                                    executing the BreakHandler page.

                                  One purpose of idle mode is to put the driver into a safe standby state when changing the clock source.
                                    If the system clock is reduced significantly while the driver is receiving or sending data not only will the
                                    data be corrupted, but it may be a long time before the driver finishes its task and loads the new settings
                                    (e.g. going from 80MHz to 13kHz is a 6000x slowdown). For this reason, in idle mode the driver always polls
                                    for changes at an interval that should work at any anticipated clock speed.
                                
                                  Since this page is called only from LoadSettings* we can inherit some values by aliasing:
                                    _idleClkfreq = _loadClkfreq = clkfreq used in last LoadSettings,
                                    _idleClkmode = _loadClkmode = clkmode used in last LoadSettings, and
                                    _idleBreakClocks = _loadBreakClocks = clocks per break threshold interval (guaranteed non-zero).

                                  There are two subtypes of idle mode -- with and without break detection: 
                                    - With break detection the polling interval is given by the following formula:
                                        pollClocks = max( min(idleMaxPollClocks, _idleBreakClocks/16), idleMinPollClocks)
                                      where min and max have their conventional meanings (not the PASM instructions), and
                                        idleMaxPollClocks = some constant that is sufficiently low enough to keep the driver responsive
                                                          at any anticipated clock speed. A value of 5000 means that the driver should respond
                                                          within half-a-second at the lowest supported speed of 10kHz.
                                        _idleBreakClocks/16 = 1/16th the break threshold in clocks, from the latest LoadSettings call.
                                        idleMinPollClocks = a constant that is sufficiently large enough to prevent the polling
                                                          loop from experiencing waitcnt rollover.
                                    - Without break detection idleMaxPollClocks is used. }

                                { Determine the poll interval, in clocks, according to the formula in the notes above. }
                                mov         _idlePoll, idleMaxPollClocks            'default if no break detection used
                                test        stateAndFlags, #cEnableBreaks   wc
                        if_c    mov         _x, _idleBreakClocks
                        if_c    shr         _x, #4                                  '_x is 1/16th of break threshold in clocks
                        if_c    max         _idlePoll, _x                           '(_x being zero is OK) 
                        if_c    min         _idlePoll, idleMinPollClocks

                                { Update driver state. }
                        if_c    movs        stateAndFlags, #cIdleWithBD
                        if_nc   movs        stateAndFlags, #cIdleNoBD
                                wrbyte      stateAndFlags, stateAddr

                                { A break condition is detected if _idleBreakClocks/_idlePoll consecutive polling intervals pass with
                                    the rx line always at zero (or one interval when _idleBreakClocks < _idlePoll). }
                        if_c    mov         _x, _idleBreakClocks                    '_idleBreakClocks is always non-zero by LoadSettings (but would be OK anyway)
                        if_c    mov         _y, _idlePoll                           '_idlePoll >= idleMinPollClocks > 0
                        if_c    call        #Divide                                 '_y = floor(_x-before/_y-before) = num poll intervals per break threshold
                                test        stateAndFlags, #cEnableBreaks   wc      'reset c after Divide call
                        if_c    mov         _idleBDReset, _y                wz      'z=1 result of division was zero (_idleBreakClocks < _idlePoll)
                  if_c_and_z    mov         _idleBDReset, #1                        '  require a minimum of one full interval in that case (would get djnz wraparound othws)
                        if_c    add         _idleBDReset, #1                        'add 1 since the djnz test occurs immediately after the reset

                                { Pre-loop setup. Given the following arrangement, the first time through the loop we will have
                                    _idlePrevCount = phsb0, and _idleCurrCount = phsb0 + 18 (todo: check).
                                  Since _idlePoll >= idleMinPollClocks > 18, there is a guaranteed countdown reset. }
                                mov         _idlePrevCount, phsb
                                mov         _idleWait_SH, cnt
                                add         _idleWait_SH, #9

                                { WARNING: any code changes inside the loop below require that idleMinPollClocks be recalculated and tested.
                                    A too-low value will cause the loop to freeze due to waitcnt rollover (53s @ 80MHz, 5 days @ 10kHz). }

:loop                           waitcnt     _idleWait_SH, _idlePoll
                        if_c    mov         _idleCurrCount, phsb
                                { Check changedFlag, clkmode, and clkfreq. We don't retain the lock since detecting a change before user code
                                    is done is harmless -- the LoadSettingsStart page will block until the user code releases the lock. 
                                  The break detection instructions ('if_c') are interleaved to take advantage of obligate hubop timing and reduce
                                    idleMinPollClocks. If a change condition occurs (z=0) they execute harmlessly. }
                                rdbyte      _x, par                         wz      'z=0 changedFlag is raised
                         if_c   mov         _idleCheck, _idlePrevCount
                         if_c   add         _idleCheck, _idlePoll                   '_idleCheck will be = _idleCurrCount IF rx line zero for entire poll interval
                        if_z    rdbyte      _x, #4
                        if_z    cmp         _x, _idleClkmode                wz      'z=0 clkmode has changed
                         if_c   mov         _idlePrevCount, _idleCurrCount
                        if_z    rdlong      _x, #0
                        if_z    cmp         _x, _idleClkfreq                wz      'z=0 clkfreq has changed
                        if_nz   jmp         #:exit                                  'exit due to settings change (z=0)

                                { Reset break detection countdown if the line was non-zero at any point in the past interval. }
                        if_c    cmp         _idleCheck, _idleCurrCount      wz      'z=0 rx line was non-zero at some point
                    if_c_and_nz mov         _idleBDCountdown, _idleBDReset

                                { Now test if a break condition exists (only 'if_c'). }
                        if_c    djnz        _idleBDCountdown, #:loop        wz      'exit (don't jump) if break condition detected (z=1)
                        if_nc   jmp         #:loop

                                { REPEAT WARNING: don't change loop above without recalculating idleMinPollClocks. }

:exit                   if_z    mov         _page, #cBreakHandler_A
                        if_nz   mov         _page, #cLoadSettingsStart_A
                                jmp         #ExecutePageA

idleMinPollClocks     long    100       'based on instructions in loop; manual count gives 89, so 100 should be safe (todo: test)
Idle_A_end
idleMaxPollClocks     long    5000      'see notes at top of code page
fit cPageALimit 'On error: page is too big.



{ CalculateBitPeriods_A
    This page calculates the bit periods based on currBaudrate and clkfreq (LONG[0]). It also calculates startBitWait.
    It is designed to pass execution on to another page specified by the _addr variable. It sets _z before executing the
  next page, which can allow another page to call this one and then return (assume _z is always set accordingly before
  calling the other page). 
    Before: _addr - index of page to execute afterwards
            lock: assumed retained if data consistency is important (baudrate and clkfreq)
    After:  _x bit 0 = 1 - bit period had to be raised to 33 clocks (baudrate too fast for clock),
                       0 - bit period was not adjusted,
               bits 1-31 undefined
            _y = two bit period, in clocks
            _z = 0 (required as flag for pages calling this one with the intention to return)
            c-flag = 0 - bit period is 34+
                     1 - bit period is 33/33.5
            lock: status unchanged
}
org cPageA
CalculateBitPeriods_A
                                { * Assumes Lock Retained * }
                                { * Assumes DriverBlock Layout * }

                                { todo: redo}

                                { todo: prove that it is not worth it to attempt 32 clock support (which tx code can handle). }

                                { Calculate two bit period. }
                                rdlong      _x, #0                                  '_x = clkfreq
                                mov         _z, par
                                add         _z, #8
                                rdlong      _y, _z                                  '_y = currBaudrate
                                min         _y, #300                                'silently enforce 300 bps minimum (can be supported at 10kHz < worst rcslow)
                                shl         _x, #1
                                call        #Divide                                 '_y = 2*clkfreq/baudrate = two bit period, in clocks
                           
                                { Limit bit period to at least 33 clocks and record if adjusted. Then determine if
                                    bit period is less than 34 clocks (a special case). } 
                                min         _y, #66                         wc      'c=1 bit period less than 33 (baudrate too fast for clock)
                                muxc        _x, #1
                                cmp         _y, #68                         wc      'c=1 bit period is 33/33.5; c=0 34+

                                { Two bit periods -- A and B -- are used to approximate the true bit period to half clock resolution. 
                                    The transmit code can support 33 clocks without problems. }
                                mov         txBitPeriodA, _y
                                shr         txBitPeriodA, #1
                                mov         txBitPeriodB, txBitPeriodA
                                test        _y, #1                          wz      'z=0 the two bit period is odd, so bit period is x.5
                        if_nz   add         txBitPeriodB, #1
                                
                                { For bit periods of 34+ the rx bit periods are the same as the tx ones. }
                        if_nc   mov         rxBitPeriodA, txBitPeriodA
                        if_nc   mov         rxBitPeriodB, txBitPeriodB
                        if_nc   mov         startBitWait, rxBitPeriodB              'startBitWait = 1/2 bit period - 10 clocks (10 clocks are 'baked-in' to wait instrs)
                        if_nc   shr         startBitWait, #1                        '(using B with the idea that truncation tends to underestimate true value)
                        if_nc   sub         startBitWait, #10                       'must be >= 5, which it will be since rxBitPeriodA >= 34

                                { Bit periods of 33/33.5 constitute a special case since the lowest supported bit period
                                    for most steps in the receive loop is 34 clocks. Sampling the stop bit as early as possible
                                    and using the lowest bit periods may allow it to work. }
                                { Todo: test this. }
                        if_c    mov         rxBitPeriodA, #34
                        if_c    mov         rxBitPeriodB, #34
                        if_c    mov         startBitWait, #5                        '5 is smallest supported

                                { In both cases -- 33/33.5 or 34+ -- rxBitPeriod5 is txBitPeriodA, since the interval after sampling
                                    bit 5 (the hubop interval) can be 33 clocks. Therefore, rxBitPeriod5 aliases txBitPeriodA. }
            
                                { All done. }
                                mov         _z, #0                                  '_z used as flag value by Idle page
                                mov         _page, _addr
CalculateBitPeriods_A_end       jmp         #ExecutePageA
fit cPageALimit 'On error: page is too big.




{ LoadSettingsStart_A

}
org cPageA
LoadSettingsStart_A


LoadSettingsStart_A_end
fit cPageALimit 'On error: page is too big.


{ LoadSettingsStart_A

}
org cPageA
LoadSettingsStart_A


LoadSettingsStart_A_end
fit cPageALimit 'On error: page is too big.

{ LoadSettingsFinish_A

}
org cPageA
LoadSettingsFinish_A

                                call        #ReleaseLock

LoadSettingsFinish_A_end
fit cPageALimit 'On error: page is too big.






org cPageA
Calc2
                                mov         _x, _loadClkFreq
                                mov         _y, #10
                                call        #Multiply
                                mov         _y, _loadBaud
                                call        #Divide
                                mov         stopBitDuration, _y
                                mov         _x, bitPeriod0
                                mov         _y, #5
                                call        #Multiply
                                sub         stopBitDuration, _x
                                mov         _x, bitPeriod1
                                shl         _x, #2
                                sub         stopBitDuration, _x
                                test        _loadOptions, #cUseTwoStopBits      wc
                        if_c    add         stopBitDuration, bitPeriod1             'stopBitDuration ready                                

                                mov         _x, _loadClkFreq
                                mov         _y, k1000
                                call        #Divide
                                mov         _loadClkPerMS, _y                              'clocks per millisecond

                                mov         _x, _loadIBTimeoutMS
                                call        #Multiply
                                mov         ibTimeout, _x                           'ibTimeout ready

                                mov         recoveryTime, _loadTwoBit
                                shl         recoveryTime, #3                        'recoveryTime ready

                                mov         _x, _loadClkPerMS
                                mov         _y, _loadBreakMS
                                call        #Multiply
                                mov         _y, recoveryTime
                                call        #Divide
                                min         _y, #1
                                mov         breakMultiple, _y                       'breakMultiple ready

                                mov         rxPhsbReset, #19
                                add         rxPhsbReset, startBitWait
                                add         rxPhsbReset, bitPeriod0                 'rxPhsbReset ready (= 5 + startBitWait + bitPeriod0 + 5 + 4 + 4 + 1)

                                mov         _page, #cCalc3
                                jmp         #ExecutePageA

Calc2_end
k1000                           long    1000

fit cPageALimit 'On error: page is too big.

org cPageA
Calc3 

                                { rxPin and txPin are one byte values in the control block. txPin is immediately
                                    after rxPin. }

                                mov         _addr, par                          'rxPin
                                add         _addr, #32
                                rdbyte      _x, _addr
                                mov         rxMask, #1
                                shl         rxMask, _x
                                movs        ctrb, _x
                                'movs        lowCounterMode, lowCounterMode
'                                mov         ctrb, lowCounterMode

                                add         _addr, #1                           'txPin (immediately after rxPin)
                                rdbyte      _x, _addr
                                mov         txMask, #1
                                shl         txMask, _x 
                                or          outa, txMask

                                call        #Trace

                                mov         _page, #cReceiveExtra_B
                                call        #LoadPageB

Calc3_end                       jmp         #RecoveryMode
fit cPageALimit 'On error: page is too big.


{ Entry
    Beginning of driver code used on launch. On launch this begins with initialization code. After
  initialization this space is used for page B.
} 
org 0
Entry
                                or          dira, pin27
                                or          outa, pin27

                                wrword      par, #8       'zero trace addresses
                                wrlong      par, #12
                                
                                jmp         #FinishInit


long 0[cPageBLimit-$]
fit cPageBLimit 'On error: Entry initialization too big.

{ Permanent code starts here. }
org cPageBLimit

{ Multiply (call)
    Algorithm from the Spin interpreter, with sign code removed.
    Before: _x = multiplier
            _y = multiplicand
    After:  _x = lower half of product
            _z = upper half of product
            _y unchanged
}
Multiply
                                mov         _z, #0
                                mov         _mathTmp_SH, #32
                                shr         _x, #1              wc
:mmul                   if_c    add         _z, _y              wc
                                rcr         _z, #1              wc
                                rcr         _x, #1              wc
                                djnz        _mathTmp_SH, #:mmul
Multiply_ret                    ret

{ Divide (call)
    Algorithm from the Spin interpreter, with sign code removed.
    Before: _x = dividend
            _y = divisor
    After:  _x = remainder
            _y = quotient
            _z undefined
}
Divide
                                mov         _z, #0
                                mov         _mathTmp_SH, #32
:mdiv                           shr         _y, #1              wc, wz
                                rcr         _z, #1
                        if_nz   djnz        _mathTmp_SH, #:mdiv
:mdiv2                          cmpsub      _x, _z              wc
                                rcl         _y, #1 
                                shr         _z, #1
                                djnz        _mathTmp_SH, #:mdiv2
Divide_ret                      ret



                                
{ ReceiveCommand
    This routine contains the receive loop used to receive and process bytes. Processing is done using shifted
  parsing instructions, which are explained in more detail in the "RX Shifted Parsing Instructions" notes.
    If all bytes of a packet have been received normally then execution goes to ReceiveCommandFinish for final
  parsing and validity checks. Otherwise, this routine may exit to HandleFramingError or ParsingErrorHandler_B.
}
ReceiveCommand
                                call        #Trace
                                xor         outa, pin27

                                { todo: check if settings have changed }

                                { Page B required for nibble table and ParsingErrorHandler_B. }
                                mov         _page, #cReceiveExtra_B
                                call        #LoadPageB

                                { pre-loop initialization }
                                mov         _RxStartWait, rxContinue
                                movs        _RxMovA, #rxFirstParsingGroup
                                movs        _RxMovB, #rxFirstParsingGroup+1
                                movs        _RxMovC, #rxFirstParsingGroup+2
                                movs        _RxMovD, #rxFirstParsingGroup+3
                                mov         _rxResetOffset, #0
                                mov         _rxWait0, startBitWait

                                test        rxMask, ina                     wz      'z=1 => rx pin already low -- missed falling edge

                        if_nz   waitpne     rxMask, rxMask                          'wait for start bit edge
                        if_nz   add         _rxWait0, cnt
                        if_nz   waitcnt     _rxWait0, rxBitPeriodA                  'wait to sample start bit
                        if_nz   test        rxMask, ina                     wc      'c=1 framing error; c=0 continue, with parser reset
                        if_z    jmp         #RecoveryMode                           '...exit for missed falling edge (need edge for accurate cont-recal)
                        if_c    jmp         #FramingErrorHandler

                                { the receive loop -- c=0 reset parser}

'loop top - occurs within interval between startbit and bit0
_RxLoopTop              if_nc   mov         _rxMixed, rxMixedReset                  'Mixed - reset byteCount, lowBitCount, writeVetoes (nonPayloadFlag is set)
                       
'bit0 - 34 clocks
:bit0                           waitcnt     _rxWait0, rxBitPeriodB
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_0001
                        if_nc   mov         phsb, rxPhsbReset                       'Cont-Recal 1 - reset low clocks count on reset; MUST change rxPhsbReset calculation if moved
                                mov         _rxLastWait1, _rxWait1                  'Cont-Recal 2 - save _rxWait1 for last byte; must come before wait transfer
                                mov         _rxWait1, _rxWait0                      'Wait 2 - transfer
                                mov         _rxWait0, startBitWait                  'Wait 3
                        if_nc   mov         _rxF16L, #0                             'F16 1 - zero checksums on reset; see page 90

'bit1 - 34 clocks
:bit1                           waitcnt     _rxWait1, rxBitPeriodA
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_0010
                        if_nc   mov         _rxF16U_SH, #0                          'F16 2
                        if_c    add         _rxF16L, _rxPrevByte                    'F16 3 - this if_c is not optional (_rxPrevByte undefined on reset, esp. high bytes)
                        if_c    cmpsub      _rxF16L, #255                           'F16 4 - the if_c's are optional from this point on for F16
                        if_c    add         _rxF16U_SH, _rxF16L                     'F16 5 - (Note on above: _rxPrevByte must have upper bytes zero for this calculation
                        if_c    cmpsub      _rxF16U_SH, #255                        'F16 6 -  to work, which is not necc. true the first pass through, but is after.)

'bit 2 - 34 clocks
:bit2                           waitcnt     _rxWait1, rxBitPeriodB
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_0100
                        if_nc   mov         _rxOffset, _rxResetOffset               'Shift 1 - go back to first parsing group on reset (see page 93)
                                subs        _rxResetOffset, _rxOffset               'Shift 2 - adjust reset offset
                                adds        _RxMovA, _rxOffset                      'Shift 3 - (next four) offset addresses for next parsing group
                                adds        _RxMovB, _rxOffset                      'Shift 4
                                adds        _RxMovC, _rxOffset                      'Shift 5

'bit 3 - 34 clocks
:bit3                           waitcnt     _rxWait1, rxBitPeriodA
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0000_1000
                                adds        _RxMovD, _rxOffset                      'Shift 6
                                mov         _rxOffset, #4                           'Shift 7 - restore default offset (must be done before shifted instructions)
_RxMovA                         mov         _RxShiftedA, 0-0                        'Shift 8 - (next four) shift parsing instructions into place
_RxMovB                         mov         _RxShiftedB, 0-0                        'Shift 9
_RxMovC                         mov         _RxShiftedC, 0-0                        'Shift 10

'bit 4 - 34 clocks
:bit4                           waitcnt     _rxWait1, rxBitPeriodB
                                testn       rxMask, ina                     wz
                                muxz        rxByte, #%0001_0000
_RxMovD                         mov         _RxShiftedD, 0-0                        'Shift 11
                                movs        _RxAddLowerNibble, rxByte               'Cont-Recal 3 - determine low bit count of lower nibble; must follow mux of bit 3
                                andn        _RxAddLowerNibble, #%1_1111_0000        'Cont-Recal 4 - (spacer required)
                                test        _rxMixed, writeVetoesMask       wz      'Write 1 - z=1 write byte to hub if all writeVetoes are clear
                        if_z    add         _rxAddr, #1                             'Write 2 - increment address (pre-increment saves re-testing the flag)

'bit 5 - 33 clocks
:bit5                           waitcnt     _rxWait1, rxBitPeriod5
                                test        rxMask, ina                     wc
_RxHubop                        long    0-0                                         'see RX Hubop; may be rxWriteByte (has 'if_z'), rxReadDriverLock, or nop

'bit 6 - 34 clocks
:bit6                           waitcnt     _rxWait1, rxBitPeriodB
                                testn       rxMask, ina                     wz
                                muxc        rxByte, #%0010_0000
                                muxz        rxByte, #%0100_0000
_RxAddLowerNibble               add         _rxMixed, 0-0                           'Cont-Recal 5 - add count of low data bits of current byte's lower nibble
                                sub         _rxCountdown, #1                wz      'Countdown - used by parsing code to determine when F16 follows payload bytes
_RxShiftedA                     long    0-0                                         'Shift 12 - (next four) execute shifted instructions
_RxShiftedB                     long    0-0                                         'Shift 13

'bit 7 - 34 clocks
:bit7                           waitcnt     _rxWait1, rxBitPeriodA
                                test        rxMask, ina                     wc
                                muxc        rxByte, #%1000_0000
_RxShiftedC                     long    0-0                                         'Shift 14
_RxShiftedD                     long    0-0                                         'Shift 15
                                mov         _rxPrevByte, rxByte                     'Handoff
                                shr         rxByte, #4                              'Cont-Recal 6 - start getting low bits count for upper nibble
                                movs        _RxAddUpperNibble, rxByte               'Cont-Recal 7 - (spacer required before Cont-Recal 8)
'stop bit
:stopBit                        waitcnt     _rxWait1, rxBitPeriodA                  'see page 98
                                testn       rxMask, ina                     wz      'z=0 framing error

_RxStartWait                    long    0-0                                         'see RX StartWait; may be rxContinue, rxExit, or rxParsingErrorExit (all 'if_z')

                        if_z    add         _rxWait0, cnt                           'Wait 1

'start bit - 34 clocks (last instr at _RxLoopTop)
:startBit               if_z    waitcnt     _rxWait0, rxBitPeriodA
                        if_z    test        rxMask, ina                     wz      'z=0 framing error
_RxAddUpperNibble       if_z    add         _rxMixed, 0-0                           'Cont-Recal 8 - finish adding low bit count for upper nibble of previous byte
                        if_z    mov         _rxTmp_SH, _rxWait0                     'Timeout 1
                        if_z    sub         _rxTmp_SH, _rxWait1                     'Timeout 2 - see page 98 for timeout notes
                        if_z    cmp         _rxTmp_SH, ibTimeout            wc      'Timeout 3 - c=0 reset, c=1 no reset
                        if_z    djnz        _rxMixed, #_RxLoopTop                   'Mixed - add to byteCount (negative)

                    { Fall through to FramingErrorHandler (djnz never gets to zero in normal operation). }

{ FramingErrorHandler (jmp)
    Invokes the framing error code page.
}
FramingErrorHandler
                                mov         _page, #cFramingError_A
                                jmp         #ExecutePageA


{ RX Hubop, used by ReceiveCommand
    These instructions are shifted into the receive loop at the _RxHubop location. The shifts must be performed
  by the shifted parsing code -- they are not done automatically.
    It does not matter which instruction is loaded on parser reset. Consider each case:
      rxWriteByte - On parser reset the nonPayloadFlag in writeVetoes (in _rxMixed) is set, so writes will not occur.
      rxReadDriverLock - Reading the driver lock state is OK -- it is intended behavior during header arrival.
    Also, _RxHubop is a nop on cog launch, so the pre-loop initialization code does not ever need to set its value.
    For future consideration: there's the potential for supporting a pool of buffers using the RX Hubop mechanism.
  This may be useful if the host is receiving errors due to user code not releasing the driver
  lock fast enough. In this case there would be three hubops: loading the next buffer set to use, checking
  if it is locked/owned, and then setting the buffer write instruction.
}
rxReadDriverLock                rdword      _rxLockingUser, driverLockAddr          'check if user code has driver lock (will be zero if unlocked)
rxWriteByte             if_z    wrbyte      _rxPrevByte, _rxAddr                    'Write 4 - write byte to command payload buffer (if writeVetoes are clear) 

{ todo: (3/28) can tx hubop be used to provide state information to ensure safety when out-cogs change clock rate? }

{ RX StartWait, used by ReceiveCommand
    These instructions are shifted to _RxStartWait in the receive loop to either receive more bytes or exit the loop.
  The 'if_z' causes the instruction to be skipped if a framing error was detected on the stop bit.
}
rxContinue              if_z    waitpne     rxMask, rxMask                          'wait for initial edge of next start bit
rxExit                  if_z    jmp         #ReceiveCommandFinish                   'finish parsing fully received packet
rxParsingErrorExit      if_z    jmp         #ParsingErrorHandler_B                  'don't exit at parsing error detection -- framing error on stop bit takes precedence


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
                    if_nz_or_c  mov         _RxStartWait, rxParsingErrorExit        ' D - ...exit for bad reserved bits (also require c = bit 7 = 0) 

rxH1                            mov         payloadSize, _rxPrevByte                'A - extract payload size
                                and         payloadSize, #$7                        ' B
                                shl         payloadSize, #8                         ' C
                                or          payloadSize, rxByte                     ' D

rxH2                            mov         _rxRemaining, payloadSize               'A - _rxRemaining keeps track of how many payload bytes are left to receive
                                mov         _rxAddr, cmdBufferResetAddr             ' B - reset address for writing command payload to hub
                                mov         port_SH, #0                             ' C - set implicit port 0
                                mov         token_SH, rxByte                        ' D - save token for responses
rxH3
                                mov         _RxHubop, rxReadDriverLock              'A - read the driver's lock state
isOpenFlag
nonPayloadFlag                  long    |< 13                                       ' B - (spacer nop) part of writeVetoes in _rxMixed; also used for flagsAndBadF16
                                mov         cmdDetails, rxByte                      ' C - save CH3 for later processing (address, mute flag, reserved bit 5)
                        if_nc   mov         _rxOffset, #12                          ' D - c = bit7 = 1 for explicit port; skip H4 and H5 if using implicit port
rxH4_Optional
kCrowPayloadLimit               long    2047                                        'A - (spacer nop) payload size limit is 11 bits in Crow v1 and v2
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
                        if_z    mov         _RxStartWait, rxExit                    'A - ...exit receive loop if no bytes in first chunk (empty payload)
                                mov         _RxHubop, rxWriteByte                   ' B - setup to write payload byte to buffer
                                cmp         _rxLockingUser, #0              wz      ' C - test if the driver is locked; z=0 driver locked by _rxLockingUser
                                muxnz       _rxMixed, driverLockedFlag              ' D - veto all buffer writes if driver is locked

{ rxP_0 - first payload byte of first chunk }
rxP_0                   if_z    mov         _rxOffset, #8                           'A - go to rxP_F16C0 if all of chunk's bytes have been received
                                andn        _rxMixed, nonPayloadFlag                ' B - clear the non-payload byte write veto (want to write payload byte to buffer)
                                or          _rxF16U_SH, _rxF16L             wz      ' C - check header's F16; z=1 OK (need F16U == F16L == 0)
                        if_nz   mov         _RxStartWait, rxParsingErrorExit        ' D - ...exit for bad header checksums

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
                        if_z    mov         _RxStartWait, rxExit                    ' B - ...exit receive loop if no bytes in next chunk (all bytes received)
driverLockedFlag                long    |< 14                                       ' C - (spacer nop) part of writeVetoes in _rxMixed
tooBigFlag                      long    |< 15                                       ' D - (spacer nop) part of writeVetoes in _rxMixed

{ rxP_CheckF16 - first payload byte in chunk, after the first chunk }
rxP_CheckF16            if_z    subs        _rxOffset, #12                          'A - go to rxP_F16C0 if all chunk payload bytes have been received
                        if_nz   subs        _rxOffset, #16                          ' B - otherwise, go to rxP_Repeating 
                                or          _rxF16U_SH, _rxF16L             wz      ' C - check chunk's F16; z=1 OK (need F16U == F16L == 0)
                        if_nz   add         flagsAndBadF16, kOneInUpperWord         ' D - increment badF16Count if chunk failed test


{ ReceiveCommandFinish
    This code runs after all packet bytes have been received (jumped to from _RxStartWait).
}
ReceiveCommandFinish
                                { Save the number of zero clock counts during the packet (the clock count for when the rx line was transmitting
                                    a zero bit). This count is used by the continuous recalibration code and some PropCrow admin commands. It is
                                    also used a reference point for detecting transaction interruptions. }
'                                mov         cmdLowClocks, phsb

                                { todo: Save the time of packet arrival to enforce any required delays. }

                                { todo: figure out at what point to do continuous recalibration }

                                { check final checksums }
                                add         _rxF16L, _rxPrevByte                    'compute F16L for last byte
                                cmpsub      _rxF16L, #255                           '(computing F16U unnecessary since it should be zero)
                                or          _rxF16U_SH, _rxF16L             wz      'z=1 OK (need F16U == F16L == 0)

                                { In the following ParsingErrorHandler_B may be called. The ReceiveExtra_B page should still be loaded
                                    from ReceiveCommand. }

                                { what to do for a bad final checksum (z=0) depends on whether it is for header or payload chunk }
                        if_nz   cmp         payloadSize, #1                 wc      'c=1 empty payload => F16 is header's
                    if_nz_and_c jmp         #ParsingErrorHandler_B                  '...exit: bad header F16 is a parsing error
                        if_nz   add         flagsAndBadF16, kOneInUpperWord         'if last payload chunk is bad, increment badF16Count and deal with it later

                                { Verify reserved bit 5 of CH3 is zero. }
                                test        cmdDetails, #%0010_0000         wc      'c=1 out of spec
                        if_c    jmp         #ParsingErrorHandler_B

                                { extract the address }
                                mov         _rxTmp_SH, cmdDetails                   'get address in _rxTmp
                                and         _rxTmp_SH, #cAddressMask        wz      'z=1 broadcast address (address 0)
                                test        cmdDetails, #cMuteFlag          wc      'c=1 mute response
                    if_z_and_nc jmp         #ParsingErrorHandler_B                  '...exit: broadcast must mute (invalid packet)

                                { At this point the packet has passed all parsing tests involving non-reportable errors. }
                                { z=1 broadcast address, c=0 open transaction (not muted), _rxTmp is address }

_RxVerifyAddress        if_nz   cmp         _rxTmp_SH, #0-0                 wz      'verify non-broadcast address; s-field set by LoadSettings
                        if_nz   jmp         #ReceiveCommand                         '...exit: packet intended for different device


                                { Now determine if a Crow transaction is open -- it is if responses aren't muted (c=0). The
                                    transaction closes when a final response is sent, or an interruption occurs.
                                  We need to set the isOpen flag of flagsAndBadF16. Also, if a transaction is open
                                    we need to retain the line (make tx pin an output).
                                  Since this is the only place a transaction can be opened we handle the details here. A transaction
                                    can close in multiple places, so that is handled with a routine (CloseTransaction). 
                                  Declaring the transaction open has to be done before checking for reportable Crow-level
                                    errors so error responses can be sent. }
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

                                { Now check some reportable Crow-level error conditions. }
                                
                                { error check: the driver is/was locked by user code (reported as IsBusy) }
                                test        _rxMixed, driverLockedFlag      wc
                        if_c    mov         _x, #cDriverLocked
                        if_c    mov         _y, _rxLockingUser
                        if_c    jmp         #ErrorHandler

                                { error check: payload size exceeded capacity }
                                test        _rxMixed, tooBigFlag            wc
                        if_c    mov         _x, #cPayloadTooBig
                        if_c    jmp         #ErrorHandler

                                { error check: bad payload checksums (count in upper word of typeAndBadF16);
                                    future: could report count of bad chunks in custom error message }
                                test        flagsAndBadF16, kUpperWordMask  wz
                        if_nz   mov         _x, #cBadPayloadChecksum
                        if_nz   jmp         #ErrorHandler

                        { A valid command packet has been received addressed to this device (or broadcast). Fall through
                            to ProcessCommand. (This transition is purely semantic -- ProcessCommand is never called explicitly.) }
ProcessCommand
                                { check command type }
                                test        flagsAndBadF16, #cCommandTypeFlag   wc  'c=1 user command

                                { if user command do port lookup elsewhere }
                        if_c    jmp         #UserPortLookup

                                { admin command -- two admin ports open: 0 and propCrowAdminPort }

                                cmp         port_SH, propCrowAdminPort      wz      'z=1 PropCrow admin command
                        if_z    mov         _page, #cPropCrowAdmin
                        if_z    jmp         #ExecutePageA

                                cmp         port_SH, #0                     wz      'z=1 standard admin from Crow specification
                        if_nz   mov         _x, #cPortNotOpen
                        if_nz   jmp         #ErrorHandler                           '...exit for admin port not open (a reportable Crow error)

                        { The command is on admin port 0, fall through to StandardAdminStart. }
 
{ StandardAdminStart
    This is the first level handler for admin commands defined by the Crow standards. The commands ping
  and hostPresence use permanent code, all other commands use paged code.
}
StandardAdminStart
                                { ping has no command payload and no response payload }
                                mov         _count, payloadSize             wz      'simultaneously test for and set up ping response (harmless if not ping)
                        if_z    jmp         #SendFinalResponse                      'safe if muted -- sending routines won't send in that case
                        
                                { for all other commands, first byte is command type }
                                rdbyte      _x, rxBufferAddr

                                { if type not 1 (echo/hostPresence) then continue on paged code }
                                cmp         _x, #1                          wz
                        if_nz   mov         _page, #cStandardAdminCont
                        if_nz   jmp         #ExecutePageA

                                { echo/hostPresence require minimum of two bytes of payload }
                                cmp         payloadSize, #2                 wc      'c=1 payload size too small (require 2+ bytes)
                        if_c    jmp         #ReceiveCommand

                                { the difference between echo/hostPresence is that echo expects a response }
                                test        flagsAndBadF16, isOpenFlag      wc      'c=1 open transaction => response expected
                        if_c    mov         _page, #cSendEcho
                        if_c    jmp         #ExecutePageA                           'echo handled with paged code

                                { The command is hostPresence, for which nothing needs to be done. It is supported as a way for the host
                                    to send inert data for continuous recalibration. }
                                
                                jmp         #ReceiveCommand


{ UserPortLookup (jmp)
    This routine is called by ReceiveCommandFinish to invoke the user code registered to the port.
}
UserPortLookup
                                mov         _page, #cUserCommand
                                jmp         #ExecutePageA



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


{ TxSendBytes (call)
    Internal routine used to send bytes. It also updates the running F16 checksum. It assumes
  the tx pin is already an output. Bytes are sent from the hub.
    This routine should not be called by user code -- use the complete or partial sending routines.
    The lowest bitPeriod supported by this routine is 32 or 33 clocks (32 clocks requires that
  the stopBitPeriod be a multiple of 2 to avoid worst case timing for hub reads).
    Before: _txAddr = address of hub bytes to send
            _txCount = number of bytes to send; IMPORTANT: must not be zero
    After:  _txAddr = address immediately after last byte sent
            _txCount = 0
    Guarantee: z-flag not modified
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


{ TxSendAndResetF16 (call)
    Internal routine to send the current F16 checksum (upper first, then lower). It 
  also resets the checksum after sending.
}
TxSendAndResetF16
                                { write F16 to hub }
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


{ SendFinalHeader, SendIntermediateHeader (both call) -- Partial Sending Routines
    The partial sending routines exist to allow sending payload bytes from multiple random
  locations of hub RAM without buffering them first. If sending an empty payload, or a payload
  from a single contiguous block of hub RAM, then it is easier to use the complete sending routines.
    Argument/Results:
        Before: _count = total payload size
        After:  _count is unchanged (unless it exceeds specification max of 2047)
    Usage:  mov     _count, <number of bytes total in payload>
            call    #SendFinalHeader
      <or>  call    #SendIntermediateHeader
      <then, if there is a payload -- repeat until all bytes sent>
            mov     _count, <number of bytes in payload fragment>       'sum of fragment sizes must equal total payload size
            mov     _addr, <address of payload fragment>
            call    #SendPayloadBytes
      <finally>
            call    #FinishSending
}
SendFinalHeader                 movs        _SendApplyTemplate, #$90                'Note: SendError assumes s-field of SendFinalHeader is RH0 template
                                jmp         #_SendEnforceSizeLimit

SendIntermediateHeader          movs        _SendApplyTemplate, #$80

_SendEnforceSizeLimit           max         _count, kCrowPayloadLimit
                                
                                { Compose header bytes RH0-RH2. RH2 (token) is constant for every response of this
                                    transaction and so it could be set once in ReceiveCommandFinish, but doing it here 
                                    saves one or two registers of permanent code. }
                                mov         _txTmp_SH, _count                       '_txTmp will be RH0
                                shr         _txTmp_SH, #8                           'this assumes _count does not exceed Crow limit
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
                                mov         _txAddr, txScratchAddr
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
                                        sendF16 flag in flagsAndBadF16 - This flag is set immediately after payload bytes have been sent and
                                                             is cleared immediately after F16 bytes have been sent. If it is set when
                                                             FinishSending is called it means the F16 bytes for the last chunk still
                                                             need to be sent (i.e. it was a remainder chunk).
                                  So, we need to set rspChunkRemaining to 128. The sendF16 is automatically cleared for the first
                                    response, but we still need to clear it for later responses when intermediates are used.   
                                }
                                mov         rspChunkRemaining, #128             'number of payload bytes remaining in the current chunk before F16 bytes
                                andn        flagsAndBadF16, #cSendF16Flag       'don't send F16 unless payload bytes sent
SendHeader_ret
SendFinalHeader_ret
SendIntermediateHeader_ret      ret
    

{ SendPayloadBytes (call) -- Partial Sending Routine
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
                _count = number of bytes to send, may be zero
        After:  _addr = address immediately after last byte sent
                _count = 0
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


{ FinishSending (call) -- Partial Sending Routine
    This routine finishes the response packet by sending the final F16 payload checksums, if necessary.
    Arguments/Results: none
}
FinishSending
                                test        flagsAndBadF16, #cSendF16Flag   wc
                        if_c    call        #TxSendAndResetF16
FinishSending_ret               ret


{ SendIntermediate (call) -- Complete Sending Routine
    This is a convenience routine for sending an intermediate response with an empty payload,
  or a payload which is at a single location.
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


{ SendFinalResponse (jmp), SendFinalAndReturn (call) -- Complete Sending Routines
    These are convenience routines for sending a final response with an empty payload, or a payload
  which is at a single location. These routines differ in what happens after the packet is sent:
  SendFinalResponse goes to ReceiveCommand after sending, SendFinalAndReturn returns to the calling code.
    Arguments/Results:
        Before: _addr = starting payload address
                _count = payload size                
        After:  _addr = address immediately after last byte sent
                _count = 0
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


{ ExecutePageA (jmp), LoadPageB (call)
    PropCrow uses paging to expand the code space. There are two paging areas:
        Page A - registers [cPageA, cPageALimit) - used for loading code that will be immediately executed
        Page B - registers [0, cPageBLimit) - used for code or constants that other code may need
    For more details see the Paging Constants notes in the CON section.
    Pages are loaded or executed by index in the page table. The page table contains both types of pages.
  It is the responsibility of the programmer to invoke the correct routine for the type of page.
    Rules:
      - For page A code execution starts at the first register of the page.
      - Pages aren't reloaded if avoidable, so code must reset itself if it self-modifies.
      - Pages aren't cached back to the hub, so they can't store information.
      - The page table is considered static (unlike the user ports table), so it is not protected by a hardware lock.
    Arguments/Results
        Before: _page = index in table of page to load or execute
        After: _page is undefined
    Usage:  mov     _page, #<page A index>
            jmp     #ExecutePageA
        -or-
            mov     _page, #<page B index>
            call    #LoadPageB
}
LoadPageB
:currPageB                      cmp         _page, #cInvalidPage            wz      'curr page B index stored in s-field (initially set to cInvalidPage)
                        if_z    jmp         LoadPageB_ret                           'return -- page already loaded

                                movs        :currPageB, _page
                                movd        _PageLoad, #0                           'page B starts at 0
                                
                                jmp         #_PageLookup
ExecutePageA
:currPageA                      cmp         _page, #cInvalidPage            wz      'curr page A index stored in s-field (initially set to cInvalidPage)
                        if_z    jmp         #cPageA                                 'exit to page if already loaded

                                movs        :currPageA, _page
                                movd        _PageLoad, #cPageA
                                movs        _PageExit, #cPageA                      'jmp to page when done

_PageLookup                     shl         _page, #2                               '@(PageTable[i]) = @PageTable + 4*i
                                add         _page, pageTableAddr
                                rdword      _pageAddr, _page                        '_pageAddr is address of page in hub
                                add         _page, #3
                                rdbyte      _pageTmp_SH, _page                      '_pageTmp is page size in longs
 
_PageLoad                       rdlong      0-0, _pageAddr
                                add         _PageLoad, kOneInDField
                                add         _pageAddr, #4
                                djnz        _pageTmp_SH, #_PageLoad
_PageExit
LoadPageB_ret                   ret


{ CloseTransaction (call)
    Used to close the transaction, preventing any more transmissions until the next command.
  Redundant calls are safe.
    Arguments/Results: none
}
CloseTransaction                andn        flagsAndBadF16, isOpenFlag              'clear isOpen flag
                                andn        dira, txMask                            'release the line (make tx pin high-z)
CloseTransaction_ret            ret


{ ErrorHandler (jmp)
    Use this routine to process low-level errors -- errors that will be reported to the host using a 
  Crow error response. This routine determines whether the error should be reported, and then calls the
  sending code if necessary. In any case execution eventually goes to ReceiveCommand. 
    Arguments/Results
        Before:  _x  = error code,
                (_y) = extra data for some custom errors
        After:  not applicable, execution goes to ReceiveCommand
}
ErrorHandler
                                test        otherOptions, #cSendErrorFlag   wc      'c=0 error responses disabled
                                test        flagsAndBadF16, isOpenFlag      wz      'z=1 no open transaction
                   if_nc_or_z   jmp         #ReceiveCommand 

                                mov         _page, #cSendError
                                jmp         #ExecutePageA


{ CopyString, CopyStringFromTable (both call)
    These routines are for copying NUL-terminated strings from one location in hub RAM to another.
  The CopyStringFromTable routine is for copying implementation defined strings that are in
  the StringTable (which is in the DatConstants block).
    Note: no NUL is written at the end of the destination string -- it will have to be added intentionally
  by the calling code. This behavior reduces code size when using these routines to assemble larger
  strings from string fragments.

  CopyString
    This routine copies a NUL-terminated string up to a given maximum size (not including the NUL).
  There must be at least _copyMaxSize free bytes starting at _copyDestAddr. No NUL is written to the 
  destination string, regardless of whether the routine encountered one in the source string or not.
    Before: _copySrcAddr = address of NUL-terminated string to copy
            _copyDestAddr = address to copy string to (NUL is never copied or written)
            _copyMaxSize = maximum size of string to copy, not including NUL
    After:  _copySrcAddr = address immediately after last byte copied (may/not have been a NUL, see z-flag)
            _copyDestAddr = address immediately after last non-NUL character
            _copySize = the size of the string copied, not including any NUL
            _copyMaxSize unchanged
            z-flag = 1: _copySrcAddr-1 is NUL, 0: _copySrcAddr-1 is not NUL

  CopyStringFromTable
    For this routine the string to copy is identified by its index in the table. The routine then loads
  the address and proceeds as with CopyString (all strings in StringTable should be NUL-terminated).
    Before: _copyIndex = the index of the string in StringTable (located in the DatConstants block)
            _copyMaxSize = maximum size of string to copy, not including NUL
            _copyDestAddr = the address to copy the string to
    After:  same as for CopyString
}
{ todo: consider non-printable character substitution }
CopyStringFromTable
                                shl         _copyIndex, #1                          '@(StringTable[i]) = @StringTable + 2*i
                                add         _copyIndex, stringTableAddr
                                rdword      _copySrcAddr, _copyIndex
CopyString
                                mov         _copyTmp_SH, _copyMaxSize
                                mov         _copySize, #0

:loop                           rdbyte      _copyByte, _copySrcAddr         wz
                                add         _copySrcAddr, #1
                        if_z    jmp         CopyString_ret                          'NUL found, exit now without copying it
                                wrbyte      _copyByte, _copyDestAddr
                                add         _copyDestAddr, #1
                                add         _copySize, #1
                                djnz        _copyTmp_SH, #:loop
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


RetainLock
                                lockset     memLockID                       wc
                        if_c    jmp         #$-1
RetainLock_ret                  ret


ReleaseLock
                                lockclr     memLockID
ReleaseLock_ret                 ret

{ Trace (call)
    Writes the current program counter and system clock (cnt) to hub for debugging.
    Usage:  call   #Trace
}
Trace                           wrword      Trace_ret, #6
                                mov         traceCnt, cnt
                                wrlong      traceCnt, #8
Trace_ret                       ret
traceCnt        long    0



{ Misc Variables and Constants}
lowCounterMode      long    $3000_0000
cmdBufferMaxSize    long    cCmdBufferMaxSize
kUpperWordMask      long    $ffff_0000

pin27 long |< 27

pause long 40_000_000

{ This is the end of permanent code. Initialization code, paged code, and res'd variables follow. (The
    initialization code -- FinishInit -- may actually start within the designated permanent code area.) }

fit cPageA 'On error: permanent code too big.

{ FinishInit
    Initialization continues here from the Entry area.
}
FinishInit
                                { todo: mechanism to guarantee only one driver cog per driver block }

                                { * Following Assumes DriverBlock Layout * }

                                mov         _addr, par

                                add         _addr, #1
                                mov         stateAddr, _addr                        'stateAddr

                                add         _addr, #96
                                rdbyte      memLockID, _addr                        'memLockID

                                { Disable the memory locking mechanism if no valid lock ID provided. }
                                cmp         memLockID, #8                       wc  'c=0 no valid lock ID
                        if_nc   mov         RetainLock, initRetainLockSkip
                        if_nc   mov         ReleaseLock, initReleaseLockSkip

                                { The next nine initialization constants can be loaded with a loop if the corresponding
                                    cog registers are in the correct sequence. }

                                mov         _initTmp_SH, #9
                                movd        :load, #cmdBuffAddr

                                add         _addr, #2

:loop                           add         _addr, #2
:load                           rdword      0-0, _addr                          'cmdBuffAddr to maxNumUserPorts
                                add         :load, kOneInDField
                                djnz        _initTmp_SH, #:loop

                                { Write the cogID field. }
                                add         _addr, #12
                                cogid       _x
                                wrbyte      _x, _addr

                                { Misc }
                                mov         frqb, #1

                                { Done with one-time initialization constants, now load settings. }

                                mov         _page, #cLoadSettingsStart_A
                                jmp         #ExecutePageA

initRetainLockSkip              jmp         RetainLock_ret
initReleaseLockSkip             jmp         ReleaseLock_ret


fit cPageALimit 'On error: FinishInit too big.


{ Res'd Variables 
    These start after the page A area. 
    Note that some variables are aliased with special purpose registers -- these are defined in the CON block.
}
org cPageALimit

{ Paging Temporaries
    These registers will be undefined after every call to ExecutePageA or LoadPageB, so alias them with care.
}
_page           res
_pageAddr       res
'_pageTmp in SPRs

{ ---- }


'_idle* must not alias _math*
'_idleWait in SPRs


_idleBDReset
_loadBaud
_rcvyCurrPhsb
_rxLastWait1
_txMaxChunkRemaining    res

_idlePoll
_loadIBTimeoutMS
_copyIndex
_rxAddr         res

_idleCountdown      'may alias _idleBreakClocks since _idleBreakClocks not used in loop
_idleBreakClocks    'must alias _loadBreakClocks
_loadBreakMS    'todo update
_copySize
_rcvyPrevPhsb
_txAddr         res

_idlePrevCount
_loadOptions
_copyMaxSize
_rxCountdown
_txCount        res

_idleClkfreq     'must alias _loadClkfreq
_loadClkFreq
_copyCount
_rxMixed  
_txNextByte     res


_idleClkmode     'must alias _loadClkmode
_loadClkMode
_copyDestAddr
_rxLockingUser
_txByte         res

_idleCheck
_loadTwoBit
_copySrcAddr
_txF16L
_rxPrevByte         res

_idleCurrCount
_loadClkPerMS
_copyByte
_txF16U
_rxRemaining        res


{ Semi-Global Variables }

rspChunkRemaining
'cmdLowBits       res

'cmdLowClocks     res

cmdZeroClocks   res
cmdZeroBits     res

payloadSize     res

{ ---- }


{ Serial Timings }
'rxBitPeriodA    res
'rxBitPeriodB    res
'rxBitPeriod5    res

'
'otherOptions    res
'
'{ Constants (after initialization) }
'accessLockID            res
'rxBufferAddr            res
'cmdBufferResetAddr      res
'txBufferAddr            res
'numUserPortsAddr        res
'maxUserPorts            res
'userPortsAddr           res
'
''maxRxPayloadSize        res
'driverLockAddr          res
'
'

{ Initialization Constants
    Starting with cmdBuffAddr, these must appear in the same order as in the driver block.
}
memLockID               res
cmdBuffAddr             res
rspBuffAddr             res
userPortsTableAddr      res
pageTableAddr           res
stringTableAddr         res
txScratchAddr
txBlockAddr             res
cmdBuffSize             res
rspBuffSize             res
maxNumUserPorts         res


{ Global Settings Variables
    These values are determined by the LoadSettings* pages.
    See also Fixed Location Global Settings Variables.
}
rxMask              res
txMask              res
rxBitPeriodA        res
rxBitPeriodB        res
startBitWait        res
stopBitDuration     res
breakMultiple       res
recoveryTime        res
ibTimeout           res
rxPhsbReset         res

minRspDelay         res
userCodeTimeout     res

{ stateAndFlags
    byte 0 - the driver state; WriteState writes this byte to the driver block for diagnostic and runtime use by outside code
    bit 9 - not used; this allows using movs to set the state
    bit 10 - enableBreaksFlag

}
stateAndFlags       res
stateAddr           res

{ Argument/Result Variables
    The following registers are never used by the sending or utility routines except as calling arguments
  or return results, in which case that use is clearly stated.
    These registers are used by the receiving code (_rx), which means they will be undefined immediately
  after a command is received, but their values will be stable and predictable after that.
}
fit 489 'On error: Too many res'd variables.
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


{ Fixed Location Global Settings Variables
    The transmit loop uses a bit twiddling mechanism to toggle between the two bit periods. This requires
  that txBitPeriodA be at an even address, and txBitPeriodB immediately follow it.
}
fit 494
org 494

rxBitPeriod5            'aliases txBitPeriodA (see CalculateBitPeriods)
txBitPeriodA    res     'must be at even address
txBitPeriodB    res     'must be at address immediately after txBitPeriodA


{ Payload Buffers
    The sizes are set in the CON section.
    The payload buffers must be long-aligned.
}
CmdBuffer           long    0[cCmdBuffSizeInLongs]
RspBuffer           long    0[cRspBuffSizeInLongs]

{ UserPortsTable
    
}
UserPortsTable      word    0[3*cMaxNumUserPorts]



