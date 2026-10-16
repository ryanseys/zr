require "pty"

# Each descriptor that PTY gives the program closes across an exec, the
# writer of a spawn too, which pty.c makes with rb_cloexec_dup.
PTY.open do |m, s|
  p [:open, m.close_on_exec?, s.close_on_exec?]
end

r, w, pid = PTY.spawn("/bin/sh", "-c", "exit 0")
p [:spawn, r.close_on_exec?, w.close_on_exec?, r.fileno != w.fileno]
r.close
w.close
Process.wait(pid)

PTY.spawn("/bin/sh", "-c", "exit 0") do |reader, writer, _|
  p [:block, reader.close_on_exec?, writer.close_on_exec?]
  # The child sees neither of the parent's ends.
  out = IO.popen(["/bin/sh", "-c", "ls /dev/fd/#{reader.fileno} /dev/fd/#{writer.fileno} 2>/dev/null | wc -l"], &:read)
  p [:child_sees, out.to_i]
  reader.close
  writer.close
end
