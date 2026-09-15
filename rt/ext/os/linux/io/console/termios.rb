# frozen_string_literal: true

# Linux's struct termios, as io/console reads and writes it: four flag
# ints, the line discipline, then 32 control characters, and the flags
# each mode changes, as musl spells them.
class IO
  TERMIOS_FLAG_BYTES = 4
  TERMIOS_FLAG_PACK = "L<"
  TERMIOS_IFLAG = 0
  TERMIOS_OFLAG = 4
  TERMIOS_CFLAG = 8
  TERMIOS_LFLAG = 12
  TERMIOS_VMIN = 17 + 6
  TERMIOS_VTIME = 17 + 5
  # tcsetattr's action, and tcflush's queue.
  TCSANOW = 0
  TCIFLUSH = 0
  TCOFLUSH = 1
  TCIOFLUSH = 2
  # musl's cfmakeraw, then ECHOE and ECHOK, as console.c's set_rawmode
  # clears them.
  RAW_IFLAG_OFF = 0x5eb   # IGNBRK BRKINT PARMRK ISTRIP INLCR IGNCR ICRNL IXON
  RAW_OFLAG_OFF = 0x1     # OPOST
  RAW_LFLAG_OFF = 0x807b  # ECHO ECHOE ECHOK ECHONL ICANON ISIG IEXTEN
  RAW_CFLAG_OFF = 0x130   # CSIZE PARENB
  RAW_CFLAG_ON = 0x30     # CS8
  COOKED_IFLAG_ON = 0x522 # BRKINT ISTRIP ICRNL IXON
  COOKED_LFLAG_ON = 0x807b
  # What an interrupt needs back: BRKINT, ISIG and OPOST.
  INTR_IFLAG = 0x2
  INTR_LFLAG = 0x1
  INTR_OFLAG = 0x1
  # set_echo and set_noecho, and the pair echo_p reads.
  ECHO_BITS = 0x78        # ECHO ECHOE ECHOK ECHONL
  ECHO_ANY = 0x48         # ECHO ECHONL
  private_constant :TERMIOS_FLAG_BYTES, :TERMIOS_FLAG_PACK, :TERMIOS_IFLAG, :TERMIOS_OFLAG, :TERMIOS_CFLAG,
                   :TERMIOS_LFLAG, :TERMIOS_VMIN, :TERMIOS_VTIME, :TCSANOW, :TCIFLUSH, :TCOFLUSH, :TCIOFLUSH,
                   :RAW_IFLAG_OFF, :RAW_OFLAG_OFF, :RAW_LFLAG_OFF, :RAW_CFLAG_OFF, :RAW_CFLAG_ON,
                   :COOKED_IFLAG_ON, :COOKED_LFLAG_ON, :INTR_IFLAG, :INTR_LFLAG, :INTR_OFLAG,
                   :ECHO_BITS, :ECHO_ANY
end
