# frozen_string_literal: true

# A `require` the compile-time splice cannot reach -- one an `if`
# guards, one inside a method or a block, one whose name only the run
# time builds -- keeps its call. The file it names is compiled as a
# UNIT, and the run-time require runs it at the position the call
# stands, which is ruby's own order: whether the call runs at all is a
# run-time fact.

puts "start"

# Inside a method: the file runs the first time the method is called,
# and a second call answers false without running it again.
def pull(name) = require_relative("lazy_units/#{name}")

p pull("counted")
p pull("counted")
p Counted.mark, COUNTED_RUNS

# Guarded: the require runs only when the guard lets it.
require_relative "lazy_units/guarded" if [].empty?
p GUARDED_MARK

# Never reached, so the file never runs.
require_relative "lazy_units/missing_is_never_asked_for" if [1].empty?

# A name the run time builds. The unit is found by the path it expands
# to, so a computed spelling reaches the same file.
%w[counted].each { |name| require_relative "lazy_units/#{name}" }
p COUNTED_RUNS

# A unit's own top-level `require_relative` splices into it, so what it
# needs is there when it runs.
p pull("nested")
p NESTED_MARK

# A computed plain `require` may name any gated builtin.
feature = "json"
require feature
p JSON.parse('{"a":[1,2]}')

# `load` runs the file again every time and answers true each time; it
# consults no loaded-feature table, so a unit -- which runs once --
# can never answer one, and the file is read where it stands.
here = File.expand_path("lazy_units", __dir__)
p load("#{here}/reloaded.rb")
p load("#{here}/reloaded.rb")
p $reloaded_runs

puts "end"
__END__
start
counted ran
true
false
:counted
1
guarded ran
:guarded
1
nested ran
true
:counted
{"a" => [1, 2]}
reloaded ran
true
reloaded ran
true
2
end
