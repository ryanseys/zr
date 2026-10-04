# Code in a refine block calls through the refinement it defines, and the
# refinement reaches the refined class for alias, alias_method and
# instance_methods; import_methods copies in modules' methods.
$stderr = $stdout
result = nil
Module.new do
  refine(String) do
    def foo; "foo"; end
    result = "hello".foo
  end
end
p result
Module.new do
  using Module.new {
    refine Array do
      alias :orig_count :count
    end
  }
  p [1,2].orig_count
end
p(([1,2].orig_count rescue $!.class))
Module.new do
  using Module.new {
    refine Array do
      alias_method :orig_count2, :count
    end
  }
  p [1,2].orig_count2
end
p(([1,2].orig_count2 rescue $!.class))
methods = Array.instance_methods
m2 = nil
Module.new { refine(Array) { m2 = instance_methods } }
p methods == m2, (methods - m2).first(5), (m2 - methods).first(5)
su = Module.new { def indent(l) = " " * l + self }
sf = Module.new { def indent(l) = "*" * l + self; def indent_star(l) = "*" * l + self }
Module.new do
  refine String do
    import_methods su, sf
    p "foo".indent(3), "foo".indent_star(2)
  end
end
Module.new do
  refine String do
    p((import_methods(Integer) rescue $!.message))
  end
end
