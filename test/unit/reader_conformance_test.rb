# frozen_string_literal: true

require "test_helper"
require_relative "../support/spec"
require_relative "../support/reader"

# `Zr::Reader` is a second implementation of the spec DSL. The real one
# (`Zr::Spec::DSL`) compiles and runs; the reader records and runs
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
  def test_zr_takes_the_same_keywords_on_both_roads
    assert_equal keywords(Zr::Spec::DSL, :zr), keywords(Zr::Reader::Sandbox, :zr)
  end

  def test_must_answer_takes_the_same_keywords_on_both_roads
    assert_equal keywords(Zr::Spec::Expectation, :must_answer),
                 keywords(Zr::Reader::Sandbox::Recorder, :must_answer)
  end

  # Same names is not enough: an example that leaves `stderr:` out means
  # stderr **is** empty, and the two roads must mean the same by it.
  def test_must_answer_means_the_same_by_a_keyword_left_out
    assert_equal defaults(Zr::Spec::Expectation, :must_answer),
                 defaults(Zr::Reader::Sandbox::Recorder, :must_answer)
  end

  # `Zr::Spec::DSL#default_path` delegates to `Reader.path_for`, and a
  # program whose path differed between the run and the oracle would be
  # asked a different question than it answers.
  def test_a_program_is_named_for_the_file_its_example_lives_in
    assert_equal "core/fiber/fiber_test.rb", Zr::Reader.path_for("test/spec/core/fiber/fiber_test.rb")
    assert_equal "core/fiber/fiber_test.rb",
                 Zr::Reader.path_for(File.join(Zr::Reader::ROOT, "test/spec/core/fiber/fiber_test.rb"))
  end

  # The point of naming a program for its file rather than for its
  # example: a sentence can then be a sentence. Rewriting one must not
  # move the program it introduces.
  def test_renaming_an_example_cannot_move_its_program
    one = Zr::Reader.path_for("test/spec/core/hash/hash_test.rb")

    assert_equal one, Zr::Reader.path_for("test/spec/core/hash/hash_test.rb")
    assert_equal "core/hash/hash_test.rb", one
  end

  # The reader's `DEFAULTS` is what it subtracts to leave `given` holding
  # what a spec file actually wrote. A default that drifted from the
  # DSL's would make an explicit keyword vanish from `given`.
  def test_the_readers_defaults_are_the_dsls_defaults
    assert_equal defaults(Zr::Spec::DSL, :zr), Zr::Reader::Sandbox::DEFAULTS
  end

  # A spec reads a fixture through `fixture(...)`, and both roads must
  # hand it the same bytes -- the run writes them beside the program,
  # the oracle writes them beside its copy.
  def test_both_roads_read_a_fixture_the_same_way
    assert_includes Zr::Spec::DSL.ancestors, Zr::Fixtures
    assert_includes Zr::Reader::Sandbox.ancestors, Zr::Fixtures
    assert_equal File.binread("#{Zr::Fixtures::ROOT}/raising_feature/r1.rb"),
                 Zr::Fixtures.fixture("raising_feature/r1.rb")
  end

  # `fixtures(...)` is the whole `files:` hash for fixtures a program
  # reaches through `../../fixtures/`, so the name is written once.
  def test_fixtures_keys_each_name_the_way_a_program_reaches_it
    got = Zr::Fixtures.fixtures("raising_feature/r1.rb", "raising_feature/r2.rb")

    assert_equal ["../../fixtures/raising_feature/r1.rb", "../../fixtures/raising_feature/r2.rb"], got.keys
    assert_equal Zr::Fixtures.fixture("raising_feature/r1.rb"), got.values.first
  end

  def test_a_missing_fixture_says_so_rather_than_reading_nothing
    e = assert_raises(ArgumentError) { Zr::Fixtures.fixture("no/such/thing.rb") }
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
