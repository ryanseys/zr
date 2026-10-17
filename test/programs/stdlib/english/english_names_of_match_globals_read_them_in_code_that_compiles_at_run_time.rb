# English's names of the match globals ($POSTMATCH is $') read the last
# match in code that compiles as the program runs, as in code compiled
# with the program: an eval, and a file that a require finds at run time
# (test-unit's fault location detector reads $POSTMATCH).
require "English"
require "tmpdir"

"abc" =~ /b/
p [$PREMATCH, $MATCH, $POSTMATCH, $LAST_MATCH_INFO.class]
p eval('"xyz" =~ /(y)/; [$PREMATCH, $MATCH, $POSTMATCH, $LAST_PAREN_MATCH, $LAST_MATCH_INFO[1]]')
p eval('"nothing" =~ /q/; [$MATCH, $POSTMATCH, $LAST_MATCH_INFO]')

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "later.rb"), <<~RUBY)
    require "English"
    def split_entry(entry)
      return unless /\\Ablock (?:\\(.+?\\) )?in / =~ entry
      [$PREMATCH, $POSTMATCH, $LAST_MATCH_INFO.pre_match]
    end
    def last_line = ($LAST_READ_LINE = "line"; $_)
    def error_info
      raise "boom"
    rescue
      [$ERROR_INFO.message, $ERROR_POSITION.class]
    end
  RUBY
  $LOAD_PATH.unshift(dir)
  require "later"
end
p split_entry("block in test_failed"), split_entry("block (2 levels) in run"), split_entry("plain")
p last_line, error_info

# An alias that has not run is no name: an eval reads its own global.
if false
  alias $NEVER $&
end
"q" =~ /q/
p eval("$NEVER"), $NEVER
