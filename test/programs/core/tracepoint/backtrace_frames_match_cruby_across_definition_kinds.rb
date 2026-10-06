# The comprehensive frame battery, all verbatim ruby 4.0.7 (invoked as
# `-e`, the same label this harness compiles under): method labels
# (Object#m / Foo#m / Foo.cm / M.modfun / M#mixed), lexical block
# frames (`block in ...`), caller windows (0-start, past-the-top nil,
# (start, length)), re-raise preserving the original stack, custom
# backtraces (`raise cls, msg, array`, set_backtrace, nil clears,
# never-raised nil), proc frames through Proc#call, send transparency,
# and full_message's report shape. Known divergences excluded and
# catalogued: no C-method frames (`Array#each` rows), arity errors
# attribute to the call site rather than the callee's def line.

def plain; raise "x"; rescue => e; puts e.backtrace.first; end
plain
class Foo
  def m; raise "x"; rescue => e; puts e.backtrace.first; end
  def self.cm; raise "x"; rescue => e; puts e.backtrace.first; end
end
Foo.new.m
Foo.cm
module M
  def self.modfun; raise "x"; rescue => e; puts e.backtrace.first; end
  def mixed; raise "x"; rescue => e; puts e.backtrace.first; end
end
M.modfun
class Bar; include M; end
Bar.new.mixed
def with_block
  [1].each { raise "x" }
rescue => e
  puts e.backtrace[0]
end
with_block
def nested_blocks
  [1].each do
    [2].each do
      raise "x"
    end
  end
rescue => e
  puts e.backtrace[0]
end
nested_blocks
def c_inner
  puts caller.inspect
  puts caller(0).first
  puts caller(2).inspect
  puts caller(1, 1).inspect
  puts caller(9).inspect
end
def c_mid; c_inner; end
c_mid
def rr_inner; raise "orig"; end
def rr_outer
  rr_inner
rescue => e
  raise
end
begin
  rr_outer
rescue => e
  puts e.backtrace.first(3).inspect
end
begin
  raise RuntimeError, "custom", ["fake.rb:1:in 'x'", "fake.rb:2:in 'y'"]
rescue => e
  puts e.backtrace.inspect
end
e2 = RuntimeError.new("sb")
e2.set_backtrace("one_line")
puts e2.backtrace.inspect
e2.set_backtrace(nil)
puts e2.backtrace.inspect
puts RuntimeError.new("never").backtrace.inspect
def proc_caller(p) = p.call
pr = proc { raise "in proc" }
begin
  proc_caller(pr)
rescue => e
  puts e.backtrace.first(3).inspect
end
def sent; raise "via send"; end
begin
  send(:sent)
rescue => e
  puts e.backtrace.first(2).inspect
end
begin
  raise ArgumentError, "fm"
rescue => e
  puts e.full_message(highlight: false)
end
