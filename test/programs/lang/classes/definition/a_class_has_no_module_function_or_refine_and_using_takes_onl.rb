begin
  class K1; module_function :x; end
rescue NoMethodError => e
  p e.message
end
begin
  class K2; refine(String) {}; end
rescue NoMethodError => e
  p e.message
end
class K3; end
begin
  using K3
rescue TypeError => e
  p e.message
end
p "abc".singleton_class.inspect.start_with?("#<Class:#<String:0x"), String.singleton_class
