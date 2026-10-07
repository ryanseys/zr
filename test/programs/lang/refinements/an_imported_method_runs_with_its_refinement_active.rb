# A method that Refinement#import_methods copies runs with its
# refinement active: its sends find the refinement's methods, also in a
# block inside it. The module's own method, and a method that the copy
# calls, run without it, before and after the copy runs.
class Box
  def label = "box"
  def shout = label.upcase
end

module Helpers
  def describe = "#{label}:#{size}"
  def each_label = [1, 2].map { label }
  def failing = raise(ArgumentError, label)
  def through = shout
  def size = 0
end

class Plain
  include Helpers
  def label = "plain"
end

module Refined
  refine Box do
    import_methods Helpers
    def label = "refined"
    def size = 7
  end
end

module UsesIt
  using Refined

  def self.run
    box = Box.new
    out = [box.describe, box.each_label]
    begin
      box.failing
    rescue ArgumentError => e
      out << e.message
    end
    out << box.through
    out << box.describe
    out
  end
end

p Plain.new.describe
p UsesIt.run
p Plain.new.describe, Plain.new.each_label
p Box.new.label, Box.new.respond_to?(:describe)
3.times { p [UsesIt.run.first, Plain.new.describe] }
