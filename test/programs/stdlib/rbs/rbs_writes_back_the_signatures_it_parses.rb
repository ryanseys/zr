# RBS::Writer prints back what the parser read, as ruby's rbs does, and
# the environment resolves names across declarations.
require "rbs"
require "stringio"

source = <<~RBS
  module Greeter
    VERSION: String
    def self.greet: (String name, ?loud: bool) -> String
  end

  class Person
    include Greeter
    @name: String
    def initialize: (String) -> void
    def name: () -> String
    alias full_name name
  end
RBS

_, directives, decls = RBS::Parser.parse_signature(source)
io = StringIO.new
RBS::Writer.new(out: io).write(directives + decls)
puts io.string

env = RBS::Environment.new
env.add_source(RBS::Source::RBS.new(RBS::Buffer.new(name: "a.rbs", content: source), directives, decls))
env = env.resolve_type_names
p env.class_decls.keys.map(&:to_s).sort
p env.constant_decls.keys.map(&:to_s)
