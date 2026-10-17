# ruby loads rdoc, rbs, typeprof and repl_type_completor from the bundled
# gems it installs. typeprof and repl_type_completor read their types
# through rbs, whose C parser zr ports.
def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:rdoc) { require "rdoc"; RDoc::Markup::ToHtml.new.convert("= Head\n\n*bold* _em_ +code+") }
# rdoc 8's formatters take no options: ruby raises here too.
t(:rdoc_options) { RDoc::Markup::ToHtml.new(RDoc::Options.new) }
t(:rbs) { require "rbs"; RBS::Parser.parse_type("Array[Integer | String]").to_s }
t(:typeprof) do
  require "typeprof"
  service = TypeProf::Core::Service.new({})
  service.update_rb_file("t.rb", <<~RUBY)
    class Greeter
      def initialize(name) = @name = name
      def greet(loud) = loud ? @name.upcase : "hi \#{@name}"
    end
    Greeter.new("ann").greet(true)
  RUBY
  service.dump_declarations("t.rb")
end
t(:repl_type_completor) do
  require "repl_type_completor"
  [ReplTypeCompletor.analyze("[1, 2].ma", binding: binding)&.completion_candidates&.first(3),
   ReplTypeCompletor.analyze("'a'.up", binding: binding)&.completion_candidates]
end
t(:versions) { [RDoc::VERSION, RBS::VERSION, TypeProf::VERSION, ReplTypeCompletor::VERSION] }
