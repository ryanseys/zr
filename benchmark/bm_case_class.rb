# A `case` on class arms, as a compiler's tree walk does: 24 node
# classes, a few of them subclasses or with a module, and a loop over a
# mixed list of their objects. Each arm is a constant path, so the site
# selects the arm from the object's class.

module Node
  module Leaf; end
  class Base; end
  class Int < Base; include Leaf; end
  class Str < Base; include Leaf; end
  class Sym < Base; include Leaf; end
  class Nil < Base; include Leaf; end
  class Ivar < Base; include Leaf; end
  class Gvar < Base; include Leaf; end
  class Lvar < Base; include Leaf; end
  class Const < Base; include Leaf; end
  class Call < Base; end
  class SafeCall < Call; end
  class Block < Base; end
  class Lambda < Base; end
  class If < Base; end
  class Unless < If; end
  class While < Base; end
  class Until < While; end
  class Seq < Base; end
  class Assign < Base; end
  class OpAssign < Assign; end
  class Def < Base; end
  class ClassDef < Base; end
  class ModuleDef < Base; end
  class Return < Base; end
  class Yield < Base; end
end

def weight(node)
  case node
  when Node::Int then 1
  when Node::Str then 2
  when Node::Sym then 3
  when Node::Nil then 4
  when Node::Ivar then 5
  when Node::Gvar then 6
  when Node::Lvar then 7
  when Node::Const then 8
  when Node::SafeCall then 9
  when Node::Call then 10
  when Node::Block then 11
  when Node::Lambda then 12
  when Node::Unless then 13
  when Node::If then 14
  when Node::Until then 15
  when Node::While then 16
  when Node::Seq then 17
  when Node::OpAssign then 18
  when Node::Assign then 19
  when Node::Def then 20
  when Node::ClassDef then 21
  when Node::ModuleDef then 22
  when Node::Return then 23
  when Node::Yield then 24
  else 0
  end
end

classes = [
  Node::Int, Node::Str, Node::Sym, Node::Nil, Node::Ivar, Node::Gvar, Node::Lvar, Node::Const,
  Node::Call, Node::SafeCall, Node::Block, Node::Lambda, Node::If, Node::Unless, Node::While,
  Node::Until, Node::Seq, Node::Assign, Node::OpAssign, Node::Def, Node::ClassDef, Node::ModuleDef,
  Node::Return, Node::Yield
]
nodes = []
i = 0
while i < 1000
  nodes << classes[(i * 7) % classes.size].new
  i += 1
end
nodes << "not a node" << 42 << nil

total = 0
n = 0
while n < 5000
  nodes.each { |x| total += weight(x) }
  n += 1
end
puts total
puts "done"
