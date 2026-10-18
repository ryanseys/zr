# Kernel's copy methods and <=> compare by identity as CRuby's C does, so
# an object that includes Kernel into a blank slate copies; <=> then asks
# its ==, which the slate does not have.
class Blank < BasicObject
  instance_methods.each { |im| undef_method im unless im == :__id__ || im == :__send__ }
end
class JustKernel < Blank
  include ::Kernel
end
o = JustKernel.new
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue ::Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 60]}"
end
t("clone") { o.clone.class }
t("dup") { o.dup.class }
t("initialize_copy") { o.send(:initialize_copy, JustKernel.new).class }
t("initialize_clone") { o.send(:initialize_clone, JustKernel.new).class }
t("initialize_dup") { o.send(:initialize_dup, JustKernel.new).class }
t("same") { o <=> o }
t("other") { o <=> 1 }
