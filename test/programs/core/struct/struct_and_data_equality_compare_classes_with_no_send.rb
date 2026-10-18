# rb_struct_equal and rb_data_equal compare the two classes as values
# (rb_obj_class(s) != rb_obj_class(s2)), so a Class#== that a program
# writes is never asked.
P = Struct.new(:a)
D = Data.define(:a)
class Class
  def ==(other)
    puts "Class#== asked"
    super
  end
end
p P.new(1) == P.new(1), P.new(1).eql?(P.new(1)), P.new(1) == Struct.new(:a).new(1)
p D.new(a: 1) == D.new(a: 1), D.new(a: 1).eql?(D.new(a: 1))
