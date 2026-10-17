# rbs's parser is C (rbs_extension); zr's port gives the same
# declarations, members, types and locations, and the same errors.
require "rbs"

source = <<~RBS
  # A point.
  class Point[T < Numeric] < Object
    attr_reader x: T
    def initialize: (x: T, ?y: T) -> void
    def +: (Point[T]) -> Point[T]
         | (T) -> Point[T]
    def self.origin: () -> Point[Integer]
  end

  module Shape : _Area
    type kind = :circle | :square | [Integer, String?]
    def area: () -> Float
  end

  interface _Area
    def area: () -> Float
  end
RBS

buffer, directives, decls = RBS::Parser.parse_signature(source)
p buffer.class, directives
decls.each do |decl|
  p [decl.class, decl.name.to_s, decl.location.start_line, decl.location.end_line]
  p decl.comment&.string
  decl.members.each do |member|
    p [member.class, member.name.to_s, member.location.source.lines.first.chomp]
    member.overloads.each { p it.method_type.to_s } if member.respond_to?(:overloads)
  end
end
point = decls.first
p point.type_params.map(&:to_s), point.super_class.name.to_s
p decls[1].self_types.map(&:to_s)
p decls[1].members.first.type.to_s

p RBS::Parser.parse_type("Hash[Symbol, ^(Integer) -> String?] | nil").to_s
p RBS::Parser.parse_method_type("[A] (A, *untyped, k: bool, **Integer) { (A) -> void } -> A").to_s
type = RBS::Parser.parse_type("Array[Integer]")
p type.location.range, type.location[:name].source, type.location[:args].source

begin
  RBS::Parser.parse_signature("class Foo\n  def x: () ->\nend\n")
rescue RBS::ParsingError => e
  p e.class, e.message, e.location.start_pos
end

tokens = RBS::Parser.lex("def foo: (Integer) -> void").value
p tokens.map { [it.type, it.location.source] }
