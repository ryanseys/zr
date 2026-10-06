e = RuntimeError.new("boom")
e.set_backtrace(["a.rb:1:in `x'", "b.rb:2"])
raise e
