# The prism an eval compiles with is the one a program requires: the
# require answers true once, and Prism then stands in Object as ruby
# stands it, while the compiler goes on working.
eval "1"
p defined?(Prism)
p require("prism"), require("prism")
p defined?(Prism), Object.constants.include?(:Prism), Prism.parse("1 + 2").value.class
p eval("[defined?(Prism), 4]")
p defined?(Ze0)

__END__
nil
true
false
"constant"
true
Prism::ProgramNode
["constant", 4]
nil
