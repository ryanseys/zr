# zr searches the same library tiers `zr build` does -- the Ruby halves of
# the runtime's extensions, the pure-Ruby ports, rubygems and bundler, and
# the store `Gemfile.lock` resolves -- so a plain `require` of a bundled gem
# reaches one library on both roads.
require "csv"
require "forwardable"
require "tempfile"
require "abbrev"

p CSV.generate_line(%w[a b c])
p Abbrev.abbrev(%w[ruby]).keys.sort

class Wrapped
  extend Forwardable
  def_delegator :@list, :size
  def initialize(list) = @list = list
end
p Wrapped.new([1, 2, 3]).size

Tempfile.create("zr") do |f|
  f.write("written")
  f.flush
  p File.read(f.path)
end

# `English` aliases a global to a match special, which prism gives a node
# type of its own.
require "English"
"hello world" =~ /o (w\w+)/
p [$MATCH, $PREMATCH, $POSTMATCH, $LAST_PAREN_MATCH]

# `tmpdir` puts a module inside its `class Dir` reopen, and a constant
# inside a `class << obj` body.
require "tmpdir"
p Dir.tmpdir.is_a?(String)

# A spliced file records itself in `$LOADED_FEATURES` before it runs, the
# way CRuby's `rb_provide_feature` does.
p $LOADED_FEATURES.any? { |f| f.end_with?("abbrev.rb") }
