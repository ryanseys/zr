# A descriptor opened for writing alone becomes a stream with no mode
# given, and read_nonblock says EAGAIN once in its message.
r, w = IO.pipe
x = IO.for_fd(w.fileno, autoclose: false)
p (x.write("a") rescue $!), (x.read rescue $!)
r, w = IO.pipe
begin; r.read_nonblock(1); rescue => e; p e.message, e.class, e.detailed_message; end
begin; IO.new(r.fileno, autoclose: false).read_nonblock(1); rescue => e; p e.message; end

__END__
1
#<IOError: not opened for reading>
"Resource temporarily unavailable - read would block"
IO::EAGAINWaitReadable
"Resource temporarily unavailable - read would block (IO::EAGAINWaitReadable)"
"Resource temporarily unavailable - read would block"
