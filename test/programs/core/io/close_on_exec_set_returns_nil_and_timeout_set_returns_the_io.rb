# rb_io_set_close_on_exec returns nil; rb_io_set_timeout returns the IO.
io = File.open(__FILE__)
p [io.close_on_exec?, io.send(:close_on_exec=, 42), io.close_on_exec?, io.send(:close_on_exec=, nil), io.close_on_exec?]
p((io.close_on_exec = true))
r, = IO.pipe
p [1, 1.2, 3r, nil].map { |v| [r.send(:timeout=, v).equal?(r), r.timeout] }
p((r.timeout = 5))
