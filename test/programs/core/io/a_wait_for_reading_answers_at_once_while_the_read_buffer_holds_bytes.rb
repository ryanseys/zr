# IO#wait, #wait_readable and #wait_priority answer at once while a read
# left bytes in the buffer, as rb_io_read_pending decides; a nil timeout
# waits as long as IO#timeout says.
def t(label)
  print label, ": "
  p yield
rescue => e
  p [e.class, e.message]
end
r, w = IO.pipe
w.syswrite ".\n!"
t("gets") { r.gets }
t("wait(0)") { r.wait(0) }
t("wait()") { r.wait }
t("wait(:read)") { r.wait(:read) }
t("wait(:read, 0)") { r.wait(:read, 0) }
t("wait(:rw, 0)") { r.wait(:rw, 0) }
t("wait(1, 0)") { r.wait(IO::READABLE, 0) }
t("wait(5, 0)") { r.wait(IO::READABLE | IO::WRITABLE, 0) }
t("wait(:priority)") { r.wait(:priority, 0) }
t("wait_readable(0)") { r.wait_readable(0) }
t("wait_priority(0)") { r.wait_priority(0) }
t("wait_writable(0) of r") { r.wait_writable(0) }
t("wait_readable(0) of w") { w.wait_readable(0) }
t("wait_priority(0) of w") { w.wait_priority(0) }
t("wait_writable(0) of w") { w.wait_writable(0).equal?(w) }
t("wait_writable(1, 2) of w") { w.wait_writable(1, 2) }
t("wait(:read, 0) of w") { w.wait(:read, 0) }
t("wait(1, 0) of w") { w.wait(1, 0) }
t("wait(1, 'x')") { r.wait(1, "x") }
t("wait(:read, 'x')") { r.wait(:read, "x") }
t("wait(0, 0)") { r.wait(0, 0) }
t("read rest") { r.read_nonblock(10) }
t("wait(0) empty") { r.wait(0) }
t("wait(1, 0) empty") { r.wait(1, 0) }
t("wait_readable(0) empty") { r.wait_readable(0) }
t("wait_priority(0) empty") { r.wait_priority(0) }
r.timeout = 0.05
t("wait_readable with IO#timeout") { r.wait_readable }
t("wait with IO#timeout") { r.wait }
t("wait(1, nil) with IO#timeout") { r.wait(1, nil) }
r.timeout = nil
w.syswrite "x"
t("wait_readable ready") { r.wait_readable(1).equal?(r) }
t("wait(1, 1) ready") { r.wait(1, 1) }
r.close
t("closed wait_readable") { r.wait_readable(0) }
t("closed wait") { r.wait(1, 0) }
t("closed wait(:read)") { r.wait(:read, 0) }
