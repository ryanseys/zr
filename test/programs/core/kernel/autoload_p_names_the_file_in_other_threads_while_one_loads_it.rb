# While one thread reads an autoload's file, autoload? gives nil in that
# thread and the file in any other, before and after the file defines the
# constant.
require "tmpdir"

module AdMod; end
module AdChild
  include AdMod
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "during.rb")
  File.write(path, <<~RUBY)
    $results << AdMod.autoload?(:During)
    $others << Thread.new { [AdMod.autoload?(:During), AdChild.autoload?(:During), AdMod.autoload?(:During, false)] }.value
    module AdMod
      During = 1
    end
    $results << AdMod.autoload?(:During)
    $others << Thread.new { AdMod.autoload?(:During) }.value
  RUBY
  $results = []
  $others = []
  AdMod.autoload :During, path
  $results << (AdMod.autoload?(:During) == path)
  AdMod::During
  $results << AdMod.autoload?(:During)
  p $results
  p($others.flatten.map { |x| x == path })
end
