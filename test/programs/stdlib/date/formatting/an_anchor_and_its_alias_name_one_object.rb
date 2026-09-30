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

# --- Anchors and aliases -------------------------------------------------
show("simple alias") { YAML.unsafe_load("a: &x 1\nb: *x") }
show("container alias") { YAML.unsafe_load("a: &x [1]\nb: *x") }
show("alias shares identity") do
  v = YAML.unsafe_load("a: &x [1]\nb: *x")
  v["a"].equal?(v["b"])
end
show("self-referential seq") do
  v = YAML.unsafe_load("--- &1\n- *1\n")
  [v.size, v.first.equal?(v)]
end
show("self-referential map") do
  v = YAML.unsafe_load("--- &1\na: *1\n")
  v["a"].equal?(v)
end
show("mutual") do
  v = YAML.unsafe_load("a: &a\n  b: &b\n    c: *a\n")
  v["a"]["b"]["c"].equal?(v["a"])
end
show("anchor reused") { YAML.unsafe_load("a: &x 1\nb: &x 2\nc: *x") }
show("undefined anchor") { YAML.unsafe_load("b: *nope") }
show("anchor on nothing") { YAML.unsafe_load("a: &x\nb: *x") }
show("alias without option") { YAML.safe_load("a: &x 1\nb: *x") }
show("many aliases") { YAML.unsafe_load("a: &x [1]\n" + (0...50).map { |i| "k#{i}: *x" }.join("\n")).size }

