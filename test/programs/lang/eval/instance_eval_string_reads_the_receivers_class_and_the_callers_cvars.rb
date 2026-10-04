# instance_eval with a String reads constants in the receiver's class
# first while it has no singleton class, and class variables in the
# caller's class. A negative first line stays negative in backtraces.
$stderr = $stdout
module RS
  FOO = :RS
  class RP; FOO = :RP; end
  class R < RP; FOO = :R; end
end
module CS
  FOO = :CS
  class CP; FOO = :CP; end
  class C < CP
    FOO = :C
    def get(o) = o.instance_eval("FOO")
  end
end
p CS::C.new.get(RS::R.new)
class Rcv; @@cvar = :rcv; end
class Clr
  @@cvar = :clr
  def get(o) = o.instance_eval("@@cvar")
  def set(o, v) = o.instance_eval("@@cv2 = v")
  def self.cv2 = @@cv2
end
p Clr.new.get(Rcv.new)
Clr.new.set(Rcv.new, 1)
p Clr.cv2
class NoCv; def get(o) = o.instance_eval("@@cvar"); end
p((NoCv.new.get(Rcv.new) rescue $!.class))
err = begin; Object.new.instance_eval("\n\nraise\n", "b_file", -100); rescue => e; e; end
p err.backtrace.first.split(":")[0..1]
module X; FOO = :x; class R; FOO = :r; end; o = R.new; p o.instance_eval("FOO"); class << o; p FOO; end; p o.instance_eval("FOO"); end
