# A `using` at the main file's toplevel changes the cref of main's frame,
# which TOPLEVEL_BINDING holds. An eval in TOPLEVEL_BINDING (ERB#result
# with no binding is one) sees the refinements of every `using` that has
# run, and none before the first.
require "erb"

module Shout
  refine Integer do
    def to_s(*) = "refined"
    def double = self * 2
  end
end

module Whisper
  refine String do
    def whisper = downcase + "..."
  end
end

def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("before using") { TOPLEVEL_BINDING.eval("1.respond_to?(:double)") }
try("ERB before") { ERB.new("x=<%= 1 + 2 %>").result }
using Shout
try("TOPLEVEL_BINDING.eval") { TOPLEVEL_BINDING.eval("[1.to_s, 3.double]") }
try("ERB#result") { ERB.new("x=<%= 1 + 2 %>").result }
try("ERB#result double") { ERB.new("<%= 4.double %>").result }
try("ERB#result_with_hash") { ERB.new("<%= x %>").result_with_hash(x: 1) }
try("Kernel#eval with it") { eval("5.double", TOPLEVEL_BINDING) }
try("whisper before its using") { TOPLEVEL_BINDING.eval("'AB'.whisper") }
using Whisper
try("both") { TOPLEVEL_BINDING.eval("['AB'.whisper, 2.double]") }
try("binding here") { binding.eval("['CD'.whisper, 3.to_s]") }
try("a method's eval") do
  def evals = TOPLEVEL_BINDING.eval("6.double")
  evals
end
class Plain
  def self.run = TOPLEVEL_BINDING.eval("7.double")
end
try("from a class") { Plain.run }
try("interpolated") { TOPLEVEL_BINDING.eval('"#{8}"') }
