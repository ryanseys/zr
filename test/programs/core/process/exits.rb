begin; abort "msg"; rescue SystemExit => e; p e.message, e.status; end
begin; abort; rescue SystemExit => e; p e.message, e.status; end
begin; exit; rescue SystemExit => e; p e.message, e.status, e.success?; end
begin; exit false; rescue SystemExit => e; p e.status; end
begin; exit 7; rescue SystemExit => e; p e.status; end
begin; fail "f"; rescue => e; puts e.backtrace; end
def m = exit(2)
begin; m; rescue SystemExit => e; puts e.backtrace; end
p(exit("x")) rescue p $!
p(exit(nil)) rescue p $!
begin; abort nil; rescue TypeError => e; puts e.message, e.backtrace; end
begin; abort 3; rescue TypeError => e; puts e.message; end
p at_exit { }.class
begin; at_exit; rescue => e; p e; end
p Kernel.respond_to?(:puts), Kernel.private_instance_methods.include?(:puts)
Kernel.puts "hi"
Kernel.p 1, 2
::Kernel.print "a", "b\n"
p Kernel.Integer("3"), Kernel.String(4), Kernel.Array(nil), Kernel.format("%03d", 7), Kernel.sprintf("%s", :x)
p Kernel.block_given?, Kernel.lambda { }.lambda?, Kernel.proc { }.lambda?
x = Kernel.catch(:t) { Kernel.throw :t, 9 }
p x
p Kernel.loop { break 3 }
begin; Kernel.raise ArgumentError, "boom"; rescue => e; p e; end
begin; Kernel.fail "f"; rescue => e; p e; end
p Kernel.__method__
p Kernel.singleton_class.instance_method(:puts).owner
p Kernel.method(:puts).arity
p Kernel.instance_method(:puts).owner
p Kernel.method(:puts).owner
at_exit { warn "handler one"; puts "one" }
at_exit { puts "two"; exit 4 }
at_exit { raise "in handler" }
puts "body"
raise "boom"
