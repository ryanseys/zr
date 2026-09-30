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

# --- Round trips ---------------------------------------------------------
[
  { "a" => 1 },
  { "a" => [1, 2, { "b" => nil }] },
  [1.5, -0.0, true, false, nil, "x"],
  { "s" => "l1\nl2\n" },
  { "s" => "l1\nl2" },
  { nil => 1 },
  { :sym => :other },
  "héllo",
  ["", " x", "x ", "017", "true", "a: b"],
  1..3
].each_with_index do |v, i|
  show("round trip #{i}") { YAML.unsafe_load(YAML.dump(v)) == v }
end
