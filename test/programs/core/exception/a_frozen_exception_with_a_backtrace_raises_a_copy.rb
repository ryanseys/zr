e = RuntimeError.new("f").freeze
begin; raise e; rescue => x; p x.equal?(e), x.backtrace; end
e2 = RuntimeError.new("g")
e2.set_backtrace(["q:1"])
e2.freeze
begin; raise e2; rescue => x; p x.equal?(e2), x.backtrace, x.frozen?; end
