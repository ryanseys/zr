# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/ze0"

ROOT = File.expand_path("../..", __dir__)

# ze0 on `program`, written as `p.rb` in a scratch directory so the file
# name's length in the text never moves. Answers the CLIF text.
def ze0_text(program)
  Dir.mktmpdir("ze0-check-") do |dir|
    File.write(File.join(dir, "p.rb"), program)
    Dir.chdir(dir) { Ze0.compile(program, "p.rb").first }
  end
end
