# The runtime's helper classes, which ruby writes in C, are not modules
# that ObjectSpace or Class#subclasses shows.
names = ObjectSpace.each_object(Module).filter_map(&:name)
p names.grep(/\A(Regexp::Onig|Regexp::Pattern|Dir::Glob|File::FnMatch|Marshal::Reader|Marshal::Writer|Packing|Kernel::Formatter)/)
p Object.subclasses.map(&:name).grep(/Marshal|Glob|FnMatch|Redirects/)
n = RubyVM::AbstractSyntaxTree.parse("1 + 2")
p n.instance_variables, RubyVM::AbstractSyntaxTree::Node.constants, RubyVM::AbstractSyntaxTree::Node.singleton_methods
p RubyVM::AbstractSyntaxTree::Node.private_instance_methods(false), (RubyVM::AbstractSyntaxTree::Node.new rescue $!)
