# Three bodies, so a MIDDLE install has to clear and re-mark.
class TH
  def m = "t1"
  private :m
end
p [(TH.new.m rescue $!.class.to_s), TH.new.send(:m)]
class TH
  def m = "t2"
end
p TH.new.m
class TH
  def m = "t3"
  private :m
end
p [(TH.new.m rescue $!.class.to_s), TH.new.send(:m)]

