# A method with no redefinition at all keeps the ordinary static path.
class ST
  def a = "a"
  def b = "b"
  private :b
end
p [ST.new.a, (ST.new.b rescue $!.class.to_s), ST.private_instance_methods(false)]
