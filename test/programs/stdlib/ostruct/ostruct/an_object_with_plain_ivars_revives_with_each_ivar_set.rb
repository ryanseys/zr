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

show("plain ivars") do
  YAML.unsafe_load("--- !ruby/object:PlainIvars\nname: bolt\nsize: 3\n")
end

