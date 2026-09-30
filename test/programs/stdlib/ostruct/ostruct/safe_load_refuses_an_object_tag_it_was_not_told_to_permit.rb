# `!ruby/...` tags, and the three ways an object gets filled back in.
#
# This is the half of psych that turns a document into OBJECTS rather than
# into hashes: `Gem::Specification.from_yaml` reads a `.gem` through it, and
# before it existed a `!ruby/object:Gem::Specification` loaded as a Hash and
# rubygems reported "YAML data doesn't evaluate to gem specification".
#
# Psych fills a revived object in a fixed order, and each rung is here:
# `init_with(coder)` first, `yaml_initialize(tag, map)` next, and plain ivar
# assignment last.

require "yaml"
require "ostruct"

# --- the three fill routes ------------------------------------------------
class PlainIvars
  attr_reader :name, :size
  def inspect = "#<PlainIvars name=#{@name.inspect} size=#{@size.inspect}>"
end

class KnowsInitWith
  attr_reader :seen, :tag
  def init_with(coder)
    @tag = coder.tag
    @seen = coder.map
  end
  def inspect = "#<KnowsInitWith tag=#{@tag.inspect} seen=#{@seen.inspect}>"
end

class KnowsYamlInitialize
  attr_reader :seen, :tag
  def yaml_initialize(tag, vals)
    @tag = tag
    @seen = vals
  end
  def inspect = "#<KnowsYamlInitialize tag=#{@tag.inspect} seen=#{@seen.inspect}>"
end

# A class whose `initialize` refuses no-argument construction: psych must
# ALLOCATE rather than call `new`, and this is what proves it does.
class RefusesNew
  attr_reader :a
  def initialize(a) = (@a = a)
  def inspect = "#<RefusesNew a=#{@a.inspect}>"
end

Point = Struct.new(:x, :y)

def show(label)
  puts "#{label}\t#{yield.inspect}"
rescue StandardError => e
  puts "#{label}\t#{e.class}: #{e.message}"
end

# --- what safe_load refuses, and what naming a class permits --------------
GATED = {
  "object" => "--- !ruby/object:PlainIvars\nname: bolt\n",
  "struct" => "--- !ruby/struct:Point\nx: 1\ny: 2\n",
  "exception" => "--- !ruby/exception:ArgumentError\nmessage: bad\n",
  "class" => "--- !ruby/class 'String'\n",
  "module" => "--- !ruby/module 'Comparable'\n",
  "regexp" => "--- !ruby/regexp /a/\n",
  "string sub" => "--- !ruby/string:String hi\n",
  "array sub" => "--- !ruby/array:Array\n- 1\n",
  "hash sub" => "--- !ruby/hash:Hash\na: 1\n",
  "range" => "--- !ruby/range\nbegin: 1\nend: 2\nexcl: false\n",
  "set" => "--- !!set\n? a\n",
  "omap map" => "--- !!omap\na: 1\n",
  # A sequence is the one shape psych does NOT gate: its sequence visitor
  # never reaches the class loader for these tags.
  "omap seq" => "--- !!omap\n- a: 1\n",
  "object seq" => "--- !ruby/object:PlainIvars\n- 1\n",
  "range seq" => "--- !ruby/range\n- 1\n",
  "set seq" => "--- !!set\n- a\n",
}.freeze

GATED.each do |name, doc|
  show("gated #{name}") { YAML.safe_load(doc) }
end

