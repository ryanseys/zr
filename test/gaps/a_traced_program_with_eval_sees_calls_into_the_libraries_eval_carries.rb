# A program that evals and traces sees the calls of the libraries it
# requires, also those that eval itself carries (pp, prettyprint, json),
# and its method hooks run as those libraries load.

p eval("1 + 1")

added = []
Module.prepend(Module.new do
  define_method(:method_added) { |name| added << name if self.name == "PrettyPrint" && name == :text; super(name) }
end)
require "prettyprint"
p added

seen = []
point = TracePoint.new(:call) { |tp| seen << tp.method_id if tp.defined_class == PrettyPrint }
point.enable { PrettyPrint.format(+"") { |q| q.text "hi" } }
p seen.uniq.sort
