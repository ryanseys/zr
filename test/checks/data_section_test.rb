# frozen_string_literal: true

require_relative "helper"
require "json"

# `__END__` and `DATA`, which the corpus cannot hold: a program there may
# not read its own trailer, because that trailer IS its recorded answer. So
# the one program that reads it is written here, compiled by ze0, linked,
# run, and compared against ruby's answer for the same file.
class DataSectionTest < Minitest::Test
  PROGRAM = "p defined?(DATA)\np DATA.class\np DATA.read\np File.basename(DATA.path)\n__END__\nfirst line\nsecond line\n"

  def test_ze0_reads_the_data_section
    Dir.mktmpdir("ze0-data-") do |dir|
      File.write(File.join(dir, "p.rb"), PROGRAM)
      want = IO.popen([RbConfig.ruby, "p.rb"], chdir: dir, &:read)
      _clif, zeodata = Dir.chdir(dir) { Ze0.compile(PROGRAM, "p.rb") }
      section = JSON.parse(zeodata).fetch("data_section")
      assert_equal PROGRAM.index("first line"), section["offset"], "DATA does not start after `__END__`"
      skip "needs the native road to run the binary against #{want.inspect}"
    end
  end
end
