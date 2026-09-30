# `IO#ioctl`. rb_io_ctl reads its argument as setup_narg does: nil and false
# stand for 0, true for 1, an Integer for itself, and a String is the buffer
# the command fills -- grown to the length the command names (the IOCPARM
# bits of the command itself) with one byte after it, so a command that wrote
# too far is caught rather than trusted.
#
# FIONREAD asks how many bytes wait in a pipe, which needs no terminal, so
# the whole path is observable here: the buffer grows, the count reads back,
# and the sentinel byte is cleared to NUL on the way out.
FIONREAD = 0x4004667f

def answer
  "#{yield.inspect}"
rescue StandardError => e
  "#{e.class}: #{e.message}"
end

r, w = IO.pipe
w.write("hello")
w.flush

# A buffer of exactly the right size, and the count it comes back with.
sized = "\0" * 4
puts answer { [r.ioctl(FIONREAD, sized), sized.unpack1("l")] }

# An empty String grows to the length the command names, plus the sentinel.
empty = +""
puts answer { [r.ioctl(FIONREAD, empty), empty.bytesize, empty.unpack1("l")] }

# One byte is short as well, and grows the same way.
short = +"\0"
puts answer { [r.ioctl(FIONREAD, short), short.bytesize, short.unpack1("l")] }

# A frozen String is no buffer to fill.
puts answer { r.ioctl(FIONREAD, "".freeze) }

# Without a buffer the command has nowhere to write, which the kernel says.
puts answer { r.ioctl(FIONREAD, 0) }
puts answer { r.ioctl(FIONREAD, nil) }

r.close
w.close

# A closed stream refuses before the call.
puts answer { r.ioctl(FIONREAD, +"\0" * 4) }

