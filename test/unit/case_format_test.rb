# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/case"

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

  def test_a_platform_s_sections_stand_in_for_macos_s_one_by_one
    c = Case.new("puts 1\n__END__\nmac\n#@ stderr\nboth\n#@ linux stdout\nlinux\n#@ linux exit 1\n#@ wasi signal 6\n")
    assert_equal Ze0::Harness::Answer.new("mac\n", "both\n", 0, nil), c.expected
    assert_equal Ze0::Harness::Answer.new("linux\n", "both\n", 1, nil), c.expected("linux")
    assert_equal Ze0::Harness::Answer.new("mac\n", "both\n", nil, 6), c.expected("wasi")
    assert_equal %i[stdout status], c.sections("linux")
    assert_empty c.sections("macos")
  end

  def test_nonl_ends_the_section_it_follows
    c = Case.new("puts 1\n__END__\nmac\n#@ linux stdout\nlinux\n#@ nonl\n")
    assert_equal "mac\n", c.expected.stdout
    assert_equal "linux", c.expected("linux").stdout
  end

  def test_only_names_the_platforms_a_program_runs_on
    c = Case.new("#@ only: macos, linux\nputs 1\n")
    assert c.runs_on?("linux")
    refute c.runs_on?("wasi")
    assert Case.new("puts 1\n").runs_on?("wasi")
    assert_raises(ArgumentError) { Case.new("#@ only: plan9\nputs 1\n") }
  end

  def test_needs_names_a_library_the_machine_must_have
    c = Case.new("#@ needs: libssl\nputs 1\n")
    assert_equal ["libssl"], c.directives.needs
    assert_equal "libssl", c.unmet_need("wasi")
    assert_nil Case.new("puts 1\n").unmet_need("wasi")
    assert_raises(ArgumentError) { Case.new("#@ needs: libfoo\nputs 1\n") }
  end

  # A program ze0 does not answer yet stays where it belongs and says
  # what it waits on, rather than moving to a directory that means it.
  def test_skip_says_what_a_gap_waits_on
    c = Case.new("#@ skip: ripper is declined\nputs 1\n__END__\n1\n")
    assert_equal "ripper is declined", c.directives.skip
    assert_nil Case.new("puts 1\n").directives.skip
  end

  def test_no_trailer_means_no_recording
    refute Case.new("puts 1\n").recorded?
    assert Case.new("puts 1\n__END__").recorded?
  end

  def test_an_unknown_directive_fails_the_case
    assert_raises(ArgumentError) { Case.new("#@ bogus: 1\nputs 1\n") }
  end

  def test_every_program_parses
    Dir[File.join(ROOT, "test/{e2e,bench}/**/*.rb")].reject { |rb| rb.end_with?("_test.rb") }.each do |rb|
      Case.read(rb)
    end
  end

  def test_normalize_scrubs_addresses_paths_and_thread_ids
    cwd = "/work/test"
    out = Normalize.bytes("#<Object:0x000000010276e6a8> /work/test/lang/x.rb 0xff thread 'main' (12345) panicked", "/work/test/lang/x.rb", cwd)
    assert_equal "#<Object:0xADDR> lang/x.rb 0xff thread 'main' (TID) panicked", out
  end
end
