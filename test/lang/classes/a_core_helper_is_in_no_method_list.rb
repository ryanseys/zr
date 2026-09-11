# A helper the core library keeps for itself, where CRuby has no
# method at all, shows in no list and answers no respond_to?.
p Exception.private_instance_methods(false).sort
p Exception.instance_methods(false).include?(:decorate)
p RuntimeError.new("x").respond_to?(:decorate, true)
p Exception.private_method_defined?(:decorate), Exception.method_defined?(:decorate)

e = RuntimeError.new("x")
p e.private_methods.include?(:decorate), e.methods.include?(:full_message)

# Methods the core makes for the program stay listed.
S = Struct.new(:a)
p S.instance_methods(false).sort
D = Data.define(:b)
p D.instance_methods(false).sort

__END__
[:initialize, :method_missing, :respond_to_missing?]
false
false
false
false
false
true
[:a, :a=]
[:b]
