# A stream reopens onto a pipe, which has no position to copy, as
# io_reopen skips the seek when io_tell fails (test_box.rb's
# test_lastline_not_cached_in_box).
r, w = IO.pipe
w.write("first\nsecond\n")
w.close
STDIN.reopen(r)
p gets, $stdin.gets, gets
