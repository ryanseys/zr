# A name given as a String is its bytes and their encoding, as
# String#to_sym interns it: const_set, respond_to?, attr_accessor and a
# Struct's writers name the same Symbols as the String does.
latin = Encoding::ISO_8859_1
name = "R\xe9sum\xe9".force_encoding(latin)
k = Class.new
Object.const_set(name, k)
p [k.name.encoding, Object.const_get(name.to_sym).equal?(k), Object.constants.include?(name.to_sym)]

member = "r\xe9sum\xe9".force_encoding(latin).intern
s = Struct.new(member)
p s.public_instance_methods(false).sort.map(&:encoding)
p s.new(1).respond_to?("#{member}=")

c = Class.new { attr_accessor member }
p c.public_instance_methods(false).map(&:encoding)
o = c.new
o.__send__("#{member}=", 5)
p [o.__send__(member), o.instance_variables.map(&:encoding)]

begin
  Object.const_set("Bad\xff", 1)
rescue => e
  p e.class
end
