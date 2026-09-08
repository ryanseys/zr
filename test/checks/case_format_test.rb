# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/harness/case"

# The corpus file format the sweep reads: directives above `__END__`, the
# recorded answer below it, and the scrubs that make two answers comparable.
class CaseFormatTest < Minitest::Test
  Case = Ze0::Harness::Case
  Normalize = Ze0::Harness::Normalize

  def test_a_trailer_with_every_marker
    c = Case.new("#@ args: --seed 42\nputs 1\n__END__\nAB\n#@ stderr\nwarn\n#@ exit 3\n")
    assert_equal ["--seed", "42"], c.directives.args
    assert_equal "AB\n", c.answer.stdout
    assert_equal "warn\n", c.answer.stderr
    assert_equal 3, c.answer.code
    assert_nil c.answer.signal
  end

  def test_nonl_and_escaped_marker_lines
    c = Case.new("puts 1\n__END__\n##@ not a marker\nlast\n#@ nonl\n")
    assert_equal "#@ not a marker\nlast", c.answer.stdout
  end

  def test_a_linux_section_is_kept_apart
    c = Case.new("puts 1\n__END__\nmac\n#@ linux stdout\nlinux\n#@ linux exit 1\n")
    assert_equal "mac\n", c.answer.stdout
    assert_equal "linux\n", c.linux.stdout
    assert_equal 1, c.linux.code
    assert_equal 0, c.answer.code
  end

  def test_no_trailer_means_no_recording
    refute Case.new("puts 1\n").recorded?
    assert Case.new("puts 1\n__END__").recorded?
  end

  def test_an_unknown_directive_fails_the_case
    assert_raises(ArgumentError) { Case.new("#@ bogus: 1\nputs 1\n") }
  end

  def test_every_corpus_program_parses
    Dir[File.join(ROOT, "test/{lang,core,stdlib,compiler,aot,bench,milestones,ze0,gaps}/**/*.rb")].each do |rb|
      Case.read(rb)
    end
  end

  def test_normalize_scrubs_addresses_paths_and_thread_ids
    cwd = "/work/test"
    out = Normalize.bytes("#<Object:0x000000010276e6a8> /work/test/lang/x.rb 0xff thread 'main' (12345) panicked", "/work/test/lang/x.rb", cwd)
    assert_equal "#<Object:0xADDR> lang/x.rb 0xff thread 'main' (TID) panicked", out
  end
end
