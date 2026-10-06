# A module_function copy runs the module's def, but a TracePoint names
# the module's singleton class as its defined_class, and the instance
# method keeps the module. A module that extends itself runs its instance
# method, so it names the module.

module Helpers
  module_function

  def twice(x) = x * 2
end

module Named
  def thrice(x) = x * 3
  module_function :thrice
end

module Itself
  extend self

  def once(x) = x
end

class User
  include Helpers

  def run = twice(1)
end

events = []
TracePoint.new(:call, :return) { |tp| events << [tp.event, tp.defined_class, tp.method_id] }.enable do
  Helpers.twice(1)
  Named.thrice(1)
  Itself.once(1)
  User.new.run
end
events.each { |row| p row }
