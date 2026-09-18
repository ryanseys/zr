# frozen_string_literal: true

module Ze0
  # The files a spec example hands its program, read from disk rather
  # than pasted into the example as an escaped literal.
  #
  # A `files:` value is bytes, and an example that needs a whole Ruby
  # file beside its program used to carry that file as one line of
  # escaped source -- 13 KB of it in `core/fiber`, the same 6.9 KB
  # pasted six times in `stdlib/bigdecimal`. The bytes are the same
  # bytes; what changes is that a fixture is a file you can read, run
  # and diff.
  #
  # This is one module on purpose. `Ze0::Spec::DSL` and
  # `Ze0::Reader::Sandbox` are two implementations of one DSL, and a
  # keyword added to both drifts; a helper included in both cannot.
  module Fixtures
    ROOT = File.expand_path("../fixtures", __dir__)

    module_function

    # The bytes of `test/fixtures/<name>`. Binary, because a fixture may
    # be bytes that are not text -- and because both roads write it with
    # `File.binwrite`, so an encoding tag is not something a run can see.
    def fixture(name)
      path = File.join(ROOT, name)
      raise ArgumentError, "no fixture at test/fixtures/#{name}" unless File.file?(path)

      File.binread(path)
    end
  end
end
