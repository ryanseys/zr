# The reverse order: public first, private last. The static row says private,
# so the WINDOW is what a fix has to keep public.
class RV
  def m = "rv1"
end
p RV.new.m
class RV
  private def m = "rv2"
end
p [(RV.new.m rescue $!.class.to_s), RV.new.send(:m)]

