# Line coverage counts each line that a lambda's body runs, in every
# lambda form (`->`, `lambda`, a stored one, one called with `.()`), as
# it does for a proc's.
require "coverage"
require "tmpdir"

SOURCE = <<~RUBY
  def run(a)
    -> do
      a.to_s
    end.call
    lambda do
      a.to_s
    end.call
    proc do
      a.to_s
    end.call
    -> do
      a.to_s
      a.to_s
    end.()
    stored = ->(b) do
      b.to_s
    end
    2.times { stored.call(1) }
    ->(b) do b.to_s
    end.call(1)
    ->(b) { b.to_s }.call(1)
  end
RUBY

Dir.mktmpdir do |dir|
  path = File.join(dir, "target.rb")
  File.write(path, SOURCE)
  Coverage.start(lines: true)
  require path
  run(1)
  p Coverage.result.fetch(path)[:lines]
end
