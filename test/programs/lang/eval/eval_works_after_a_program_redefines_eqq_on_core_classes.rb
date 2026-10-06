# ruby's compiler is C: what a program redefines on the core classes does
# not change how an eval compiles. Each redefinition of a basic operator
# warns under Warning[:performance].
Warning[:performance] = true
%w[NilClass TrueClass FalseClass Float Symbol String Integer].each do |klass|
  eval("class #{klass}; undef ===; def ===(*args) = args[0]; end")
end
p(nil === 0, true === 0, false === 0, 0.1 === 0, :sym === 0, "str" === 0, 0xffffffffffffffff === 0, 1 === 2)

# Code that an eval compiles now still runs.
p eval("[1, 2, 3].map { |x| x * 2 }")
p eval('case :b when :a then 1 when :b then 2 end')
p eval('case "s" when "t" then 1 else 2 end')
p eval('def twice(x) = x * 2; twice(21)')
p eval('x = "a" "b"; x + "c"')
p(/b/ =~ eval('"abc"'))

# A program's own case still uses its ===.
p(case 5 when 6 then :six end)
