# frozen_string_literal: true

require "test_helper"
require_relative "../support/spec"
require_relative "../support/reader"

# `Ze0::Reader` is a second implementation of the spec DSL. The real one
# (`Ze0::Spec::DSL`) compiles and runs; the reader records and runs
# nothing, which is what lets `rake oracle` ask ruby about every example
# without building anything.
#
# Two implementations of one DSL drift. When they do, nothing fails:
# `rake oracle` keeps passing, because it is asking the reader's model of
# the suite rather than the suite. This holds them together.
class ReaderConformanceTest < Minitest::Test
  # A keyword the reader takes and the DSL does not is the dangerous
  # direction: the reader would record a misspelled keyword happily, and
  # the oracle would pass a spec that no run could compile.
  def test_ze0_takes_the_same_keywords_on_both_roads
    assert_equal keywords(Ze0::Spec::DSL, :ze0), keywords(Ze0::Reader::Sandbox, :ze0)
  end

  def test_must_answer_takes_the_same_keywords_on_both_roads
    assert_equal keywords(Ze0::Spec::Expectation, :must_answer),
                 keywords(Ze0::Reader::Sandbox::Recorder, :must_answer)
  end

  # Same names is not enough: an example that leaves `stderr:` out means
  # stderr **is** empty, and the two roads must mean the same by it.
  def test_must_answer_means_the_same_by_a_keyword_left_out
    assert_equal defaults(Ze0::Spec::Expectation, :must_answer),
                 defaults(Ze0::Reader::Sandbox::Recorder, :must_answer)
  end

  # `Ze0::Spec::DSL#default_path` delegates to `Reader.path_for`, and a
  # program whose path differed between the run and the oracle would be
  # asked a different question than it answers.
  def test_a_program_answers_to_one_name_on_both_roads
    assert_equal "a_b_c.rb", Ze0::Reader.path_for("a b c")
    assert_includes Ze0::Spec::DSL.instance_method(:default_path).source_location.first, "spec.rb"
  end

  # The reader's `DEFAULTS` is what it subtracts to leave `given` holding
  # what a spec file actually wrote. A default that drifted from the
  # DSL's would make an explicit keyword vanish from `given`.
  def test_the_readers_defaults_are_the_dsls_defaults
    assert_equal defaults(Ze0::Spec::DSL, :ze0), Ze0::Reader::Sandbox::DEFAULTS
  end

  # A spec reads a fixture through `fixture(...)`, and both roads must
  # hand it the same bytes -- the run writes them beside the program,
  # the oracle writes them beside its copy.
  def test_both_roads_read_a_fixture_the_same_way
    assert_includes Ze0::Spec::DSL.ancestors, Ze0::Fixtures
    assert_includes Ze0::Reader::Sandbox.ancestors, Ze0::Fixtures
    assert_equal File.binread("#{Ze0::Fixtures::ROOT}/raising_feature/r1.rb"),
                 Ze0::Fixtures.fixture("raising_feature/r1.rb")
  end

  # `fixtures(...)` is the whole `files:` hash for fixtures a program
  # reaches through `../../fixtures/`, so the name is written once.
  def test_fixtures_keys_each_name_the_way_a_program_reaches_it
    got = Ze0::Fixtures.fixtures("raising_feature/r1.rb", "raising_feature/r2.rb")

    assert_equal ["../../fixtures/raising_feature/r1.rb", "../../fixtures/raising_feature/r2.rb"], got.keys
    assert_equal Ze0::Fixtures.fixture("raising_feature/r1.rb"), got.values.first
  end

  def test_a_missing_fixture_says_so_rather_than_reading_nothing
    e = assert_raises(ArgumentError) { Ze0::Fixtures.fixture("no/such/thing.rb") }
    assert_match(/no fixture at test\/fixtures/, e.message)
  end

  private

  def keywords(mod, name)
    mod.instance_method(name).parameters.select { |kind, _| kind == :key }.map(&:last).sort
  end

  # What each optional keyword is when a caller leaves it out, read off
  # the signature: `parameters` reports a keyword's name and not its
  # value, and the value is the whole point here.
  def defaults(mod, name)
    method = mod.instance_method(name)
    file, line = method.source_location
    signature = File.readlines(file)[line - 1]
    keywords(mod, name).to_h { |key| [key, eval(signature[/\b#{key}: *([^,)]+)/, 1])] }
  end
end
