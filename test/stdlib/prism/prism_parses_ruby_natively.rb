# native only: prism is linked C, which has no wasm form here
# prism, the parser ruby itself uses, linked in and reached through four
# calls: it serializes a parse into a buffer and `Prism::Serialize`, which
# is ordinary ruby, reads the bytes back into nodes.

require "prism"
puts Prism::VERSION
result = Prism.parse("x = 1 + 2\nputs x")
puts result.success?
puts result.value.class
body = result.value.statements.body
puts body.map { |node| node.class.name }.inspect
puts body.first.name.inspect
puts result.value.locals.inspect
bad = Prism.parse("def")
puts bad.success?
puts bad.errors.first.message
puts Prism.parse_success?("1 + 1")
puts Prism.parse_failure?("1 +")
puts Prism.lex("a b").value.map { |token, | token.type }.inspect
__END__
1.9.0
true
Prism::ProgramNode
["Prism::LocalVariableWriteNode", "Prism::CallNode"]
:x
[:x]
false
unexpected end-of-input; expected a method name
true
true
[:IDENTIFIER, :IDENTIFIER, :EOF]
