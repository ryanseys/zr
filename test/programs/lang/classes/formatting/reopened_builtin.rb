# A gated builtin is the runtime's half of a library whose other half is
# ruby: `require "digest"` reveals the module the runtime carries, and a
# `module Digest` after it REOPENS that module rather than shadowing it.
require "digest"

module Digest
  MARKER = :mine

  class Tag
    def initialize(name) = @name = name

    def to_s = "tag:#{@name}"
  end

  def self.marker = [MARKER, Tag.new("t").to_s]
end

# A second statement reopens the same module again, and reads what the
# first one wrote.
module Digest
  def self.again = MARKER
end

p Digest.marker
p Digest.again
p Digest.name
p Digest.instance_of?(Module)
p Digest.constants.include?(:MARKER)
p Digest.const_get(:MARKER)

# The reopen adds to the module; it does not replace it, so the native
# half is still there.
p Digest::SHA256.hexdigest("a")
p Digest::MD5.hexdigest("")

# A class written inside the reopen is the module's, under its qualified
# name, and its own instance variables are its own.
p Digest::Tag.new("x").to_s
p Digest::Tag.name
p Digest::Tag.new("y").instance_variables
