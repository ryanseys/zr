class K
  @a = 1
end
p K.instance_variable_get(:@a)
p K.instance_variable_get("@a")
p K.instance_variable_get(:@nope)
p K.instance_variables
p K.instance_variable_set(:@b, 2)
p K.instance_variables
p K.instance_variable_defined?(:@a)
p K.instance_variable_defined?(:@zz)
begin
  K.instance_variable_get(:a)
rescue NameError => e
  puts "NameError: #{e.message}"
end
