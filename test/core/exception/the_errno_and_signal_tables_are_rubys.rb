# Every Errno name ruby defines, with its errno; a name this platform
# lacks is another name for NOERROR.
p Errno.constants.size
p Errno::EWOULDBLOCK.equal?(Errno::EAGAIN), Errno::ENOKEY.name, Errno::ENOKEY::Errno
p Errno::EADV.new.message, Errno::ENOTBLK.new.message

# A rescue catches by errno.
p SystemCallError === Errno::ENOENT.new, Errno::ENOENT === SystemCallError.new(nil, 2)
p Errno::ENOENT === Errno::EPERM.new, Errno::ENOENT === "not an error"
p SystemCallError.new("m", 2).class, SystemCallError.new("m", 99999).class

# Signal.list is ruby's, aliases and all.
p Signal.list.size, Signal.list["IOT"], Signal.list["CLD"], Signal.list.keys.first(3)
p SignalException.new("WINCH").message, SignalException.new(6).message, SignalException.new("SIGCLD").signo
p SignalException.new("IOT").message, SignalException.new(0).message
p((Process.kill(:EXIT, 0) rescue $!.message))

__END__
158
true
"Errno::NOERROR"
0
"Undefined error: 0"
"Block device required"
true
true
false
false
Errno::ENOENT
SystemCallError
34
6
20
["EXIT", "HUP", "INT"]
"SIGWINCH"
"SIGABRT"
20
"SIGIOT"
"SIGEXIT"
"unsupported signal 'SIGEXIT'"
