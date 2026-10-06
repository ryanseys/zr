e = RuntimeError.new("outer")
c = ArgumentError.new("inner")
e2 = begin; raise c; rescue; RuntimeError.new("w"); end
x = RuntimeError.new("top")
begin; raise x, cause: ArgumentError.new("never raised"); rescue => e; p e.full_message(highlight: false); p e.cause.backtrace; end
