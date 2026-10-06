# Reopening a `Data.define` constant with a bare `class` runs the body as a
# `class_eval` block, and every class-body statement but a local write has a
# spelling there -- a nested class included. So `Target` keeps its members,
# and `Target.new(name:)` inside `Spec#fin!` works.
#
# Sow's `lib/sow/reap/target.rb` + `target/spec.rb` is this shape across two
# files, which `require_relative` below reproduces.

module Pkg
  Target = Data.define(:name)
  class Target
    class Spec
      def fin! = Pkg::Target.new(name: :t)
    end
    include Comparable
    def <=>(o) = name <=> o.name
  end
end
p Pkg::Target::Spec.new.fin!.name
p Pkg::Target.new(name: :b) > Pkg::Target.new(name: :a)
p Pkg::Target.ancestors.include?(Data)

require_relative "data_reopen/target"

spec = Pkg3::Target::Spec.new(:t)
spec.build { |x| x + 1 }
t = spec.fin!
p t.name, t.call(41)
p Pkg3::Target.ancestors.include?(Data)
begin
  Pkg3::Target::Spec.new(:u).fin!
rescue ArgumentError => e
  p e.message
end
