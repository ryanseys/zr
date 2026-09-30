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

# --- the other reviving tags ----------------------------------------------
show("struct") { YAML.unsafe_load("--- !ruby/struct:Point\nx: 1\ny: 2\n") }
show("struct member order") do
  # The document writes the members backwards; the struct still fills by NAME.
  YAML.unsafe_load("--- !ruby/struct:Point\ny: 2\nx: 1\n").to_a
end
show("exception") { YAML.unsafe_load("--- !ruby/exception:ArgumentError\nmessage: bad\n") }
show("exception message") do
  YAML.unsafe_load("--- !ruby/exception:ArgumentError\nmessage: bad\n").message
end
show("class") { YAML.unsafe_load("--- !ruby/class 'String'\n") }
show("module") { YAML.unsafe_load("--- !ruby/module 'Comparable'\n") }
show("regexp") { YAML.unsafe_load("--- !ruby/regexp /ab+c/im\n") }
show("regexp matches") { YAML.unsafe_load("--- !ruby/regexp /ab+c/im\n") =~ "xABBC" }
show("regexp with slash") { YAML.unsafe_load("--- !ruby/regexp /a\\/b/\n").source }
show("string subclass") { YAML.unsafe_load("--- !ruby/string:String hello\n") }
show("array subclass") { YAML.unsafe_load("--- !ruby/array:Array\n- 1\n- 2\n") }
show("hash subclass") { YAML.unsafe_load("--- !ruby/hash:Hash\na: 1\n") }
show("complex") { YAML.unsafe_load("--- !ruby/object:Complex\nreal: 1\nimage: 2\n") }
show("rational") { YAML.unsafe_load("--- !ruby/object:Rational\nnumerator: 1\ndenominator: 2\n") }
show("range") { YAML.unsafe_load("--- !ruby/range\nbegin: 1\nend: 5\nexcl: false\n") }
show("ostruct") { YAML.unsafe_load("--- !ruby/object:OpenStruct\ntable:\n  :a: 1\n") }
show("set") { YAML.unsafe_load("--- !!set\n? a\n? b\n") }
show("set class") { YAML.unsafe_load("--- !!set\n? a\n? b\n").class }
show("omap map") { YAML.unsafe_load("--- !!omap\na: 1\nb: 2\n").class }
show("omap seq") { YAML.unsafe_load("--- !!omap\n- a: 1\n- b: 2\n") }

