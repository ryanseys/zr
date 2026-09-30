# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
# At exit: cycle leak: 4 objects (Hash x3, Array x1)
# Every hostile shape the YAML loader has to survive, as ANSWERS rather
# than as a promise. The point of the file is that none of these ends the
# process: each row is either a value or a Ruby exception, and the golden
# pins which.
#
# Written when the loader was reworked to read the anchor id and the tag
# that the parser's events always carried, and it found real defects rather
# than confirming a design -- see `yaml_parser_stress.rb` for the generated
# half.
#
# ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
# about the legality of, which is a decided divergence recorded in
# `tests/yaml_backend_accepts_a_different_dialect.rb`.

require "yaml"
require "date"

def show(name)
  r = yield
  puts "#{name}\t#{r.inspect}"
rescue Exception => e
  puts "#{name}\t#{e.class}"
end

# --- Tags ----------------------------------------------------------------
show("tag str on a number") { YAML.unsafe_load("v: !!str 017")["v"] }
show("tag int on text") { YAML.unsafe_load("v: !!int '42'")["v"] }
show("tag int on garbage") { YAML.unsafe_load("v: !!int 'zz'")["v"] }
show("tag float on int") { YAML.unsafe_load("v: !!float 3")["v"] }
show("tag float on garbage") { YAML.unsafe_load("v: !!float 'zz'")["v"] }
show("tag bool") { YAML.unsafe_load("v: !!bool yes")["v"] }
show("tag binary") { YAML.unsafe_load("v: !!binary aGk=")["v"] }
show("tag binary garbage") { YAML.unsafe_load("v: !!binary '@@@'")["v"] }
show("tag binary empty") { YAML.unsafe_load("v: !!binary ''")["v"] }
show("tag omap") { YAML.unsafe_load("v: !!omap\n- a: 1\n- b: 2")["v"] }
show("tag set") { YAML.unsafe_load("v: !!set\n  ? a\n  ? b")["v"] }
show("tag unknown") { YAML.unsafe_load("v: !whatever 42")["v"] }
show("tag ruby symbol") { YAML.unsafe_load("v: !ruby/symbol foo")["v"] }
show("tag on a seq") { YAML.unsafe_load("v: !!seq [1]")["v"] }

