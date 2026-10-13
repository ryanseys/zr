module A; end
def rescued
  yield
rescue Exception => e
  [e.class, e.message.sub(__dir__, "DIR")]
end
A.autoload_relative(:B, "b.rb")
p A.autoload?(:B) == File.join(__dir__, "b.rb"), A.autoload?(:B).start_with?("/")
p A::B, A.autoload?(:B)
autoload_relative(:TOP, "top")
p Object.autoload?(:TOP) == File.join(__dir__, "top"), TOP
class K
  autoload_relative :X, "k"
end
p K.autoload?(:X) == File.join(__dir__, "k"), K::X
p rescued { eval('autoload_relative(:E, "e.rb")') }
p rescued { eval('A.autoload_relative(:E, "e.rb")') }
p rescued { eval('autoload_relative(:E, "e.rb")', binding, "/tmp/zr_x.rb") }, Object.autoload?(:E)
p rescued { A.autoload_relative(:C, 5) }
p rescued { A.autoload_relative(5, "c") }
p rescued { A.autoload_relative(:c, "c") }
p rescued { A.autoload(:c, "c") }, rescued { autoload(:"9x", "c") }
A.autoload_relative(:C, "../autoload_relative/./c.rb")
p A.autoload?(:C) == File.join(__dir__, "c.rb")
p rescued { A::C }
name = "d"
A.autoload_relative("D", name)
p A.autoload?(:D) == File.join(__dir__, "d")
o = Object.new
def o.to_path = "e2"
A.autoload_relative(:E2, o)
p A.autoload?(:E2) == File.join(__dir__, "e2")
p method(:autoload_relative).arity, Module.instance_method(:autoload_relative).arity
p Kernel.private_method_defined?(:autoload_relative), Module.public_method_defined?(:autoload_relative)
p Kernel.respond_to?(:autoload_relative)
