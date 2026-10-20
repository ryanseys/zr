# frozen_string_literal: true

# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# darwin's struct termios, as io/console reads and writes it: four flag
# words of 8 bytes, then twenty control characters, and the flags each
# mode changes, as this platform spells them.
class IO
  TERMIOS_FLAG_BYTES = 8
  TERMIOS_FLAG_PACK = "Q<"
  TERMIOS_IFLAG = 0
  TERMIOS_OFLAG = 8
  TERMIOS_CFLAG = 16
  TERMIOS_LFLAG = 24
  TERMIOS_VMIN = 32 + 16
  TERMIOS_VTIME = 32 + 17
  # tcsetattr's action, and tcflush's queue.
  TCSANOW = 0
  TCIFLUSH = 1
  TCOFLUSH = 2
  TCIOFLUSH = 3
  # cfmakeraw, then ECHOE and ECHOK, as console.c's set_rawmode clears them.
  RAW_IFLAG_OFF = 0x2fff  # IGNBRK BRKINT IGNPAR PARMRK INPCK ISTRIP INLCR IGNCR ICRNL IXON IXOFF IXANY IMAXBEL
  RAW_OFLAG_OFF = 0x1     # OPOST
  RAW_LFLAG_OFF = 0x59e   # ECHO ECHOE ECHOK ECHONL ICANON ISIG IEXTEN
  RAW_CFLAG_OFF = 0x1300  # CSIZE PARENB
  RAW_CFLAG_ON = 0x300    # CS8
  COOKED_IFLAG_ON = 0x322 # BRKINT ISTRIP ICRNL IXON
  COOKED_LFLAG_ON = 0x59e
  # What an interrupt needs back: BRKINT, ISIG and OPOST.
  INTR_IFLAG = 0x2
  INTR_LFLAG = 0x80
  INTR_OFLAG = 0x1
  # set_echo and set_noecho, and the pair echo_p reads.
  ECHO_BITS = 0x1e        # ECHO ECHOE ECHOK ECHONL
  ECHO_ANY = 0x18         # ECHO ECHONL
  private_constant :TERMIOS_FLAG_BYTES, :TERMIOS_FLAG_PACK, :TERMIOS_IFLAG, :TERMIOS_OFLAG, :TERMIOS_CFLAG,
                   :TERMIOS_LFLAG, :TERMIOS_VMIN, :TERMIOS_VTIME, :TCSANOW, :TCIFLUSH, :TCOFLUSH, :TCIOFLUSH,
                   :RAW_IFLAG_OFF, :RAW_OFLAG_OFF, :RAW_LFLAG_OFF, :RAW_CFLAG_OFF, :RAW_CFLAG_ON,
                   :COOKED_IFLAG_ON, :COOKED_LFLAG_ON, :INTR_IFLAG, :INTR_LFLAG, :INTR_OFLAG,
                   :ECHO_BITS, :ECHO_ANY
end
