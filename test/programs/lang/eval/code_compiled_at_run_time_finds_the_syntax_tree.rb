# Code compiled at run time that names RubyVM::AbstractSyntaxTree loads
# the translator that eval support carries, though the program's own
# files never name it.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

name = %w[RubyVM AbstractSyntaxTree].join("::")
t("parse") { eval("#{name}.parse('1 + 2').type") }
t("children") { eval("#{name}.parse('1 + 2').children.last.type") }
t("node class") { eval("#{name}::Node").name }
t("again") { eval("#{name}.parse('x = 1').children.last.type") }
