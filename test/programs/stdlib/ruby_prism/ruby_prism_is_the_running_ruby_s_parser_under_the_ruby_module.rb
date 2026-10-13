# ruby 4.1's Ruby::Prism: the parser of the running ruby, an autoload of
# ruby/prism under the Ruby module. Its API is the prism gem's, with its
# own classes, and it defines no top-level Prism.
require "stringio"
p Ruby.autoload?(:Prism)
p Ruby.constants.include?(:Prism)
p Ruby::Prism::VERSION, Ruby::Prism::VERSION.frozen?, Ruby::Prism::BACKEND
p Ruby.autoload?(:Prism)
p defined?(::Prism)
p Ruby::Prism.singleton_methods.sort

result = Ruby::Prism.parse("def m(a, &nil) = a + 1 # note\n")
p result.class, result.success?, result.value.class
node = result.value.statements.body.first
p node.class, node.name, node.slice, node.parameters.block.class
p result.comments.map { [_1.class, _1.slice] }
p result.source.class
p Ruby::Prism.parse("1 +").errors.map { [_1.class, _1.message, _1.location.start_offset] }
p Ruby::Prism.parse("x = 1; x", freeze: true).then { [_1.frozen?, _1.value.frozen?] }
p Ruby::Prism.parse("for (a, b), c in x; end").value.statements.body.first.index.lefts.first.class

lexed = Ruby::Prism.lex("a + 1")
p lexed.class, lexed.value.map { |token, state| [token.class, token.type, token.value, state] }
p Ruby::Prism.parse_lex("a").value.then { |tree, tokens| [tree.class, tokens.size] }
p Ruby::Prism.parse_comments("# a\n=begin\nb\n=end\n").map(&:class)
p Ruby::Prism.parse_success?("1"), Ruby::Prism.parse_failure?("1 +")
p Ruby::Prism.dump("1").start_with?("PRISM")
p Ruby::Prism.profile("1")
p Ruby::Prism.parse("x", scopes: [Ruby::Prism.scope(locals: [:x])]).value.statements.body.first.class
p Ruby::Prism.parse("x", scopes: [[:x]]).value.statements.body.first.class
p Ruby::Prism::StringQuery.local?("abc"), Ruby::Prism::StringQuery.constant?("Abc"), Ruby::Prism::StringQuery.method_name?("a=")
p Ruby::Prism.parse_stream(StringIO.new("a\nb\n")).value.statements.body.size rescue p $!.class

[
  -> { Ruby::Prism.parse("x", scopes: [1]) },
  -> { Ruby::Prism.parse(1) },
  -> { Ruby::Prism.parse("x", version: "2.0") },
  -> { Ruby::Prism.parse("1 +", raise_error: :plain) },
  -> { Ruby::Prism.parse_file("/no/such/file.rb") },
].each do |call|
  call.call
rescue Exception => e
  p [e.class, e.message.lines.first.chomp]
end

visitor = Class.new(Ruby::Prism::Visitor) do
  attr_reader :calls
  def visit_call_node(node)
    (@calls ||= []) << node.name
    super
  end
end.new
Ruby::Prism.parse("a.b(c)").value.accept(visitor)
p visitor.calls
p Ruby::Prism.parse("1").value.statements.body.first.deconstruct_keys([:value])
