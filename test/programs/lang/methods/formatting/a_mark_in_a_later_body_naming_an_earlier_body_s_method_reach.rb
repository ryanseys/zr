# A mark written in a LATER body, naming a method an EARLIER body defined --
# the deferred `MethodVisibility` path rather than the in-place retag.
class LT
  def m = "lt1"
end
p LT.new.m
class LT
  private :m
end
p [(LT.new.m rescue $!.class.to_s), LT.new.send(:m)]

