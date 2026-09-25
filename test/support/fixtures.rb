# frozen_string_literal: true

module Zr
  # Reads the files that a spec example needs from disk. A fixture is a
  # file that a maintainer can read, run and diff, not an escaped string
  # literal in the spec.
  #
  # Use a fixture also for expected output that is too large to read
  # inline, for example `must_answer fixture("core/object/method_owners.out")`.
  #
  # `Zr::Spec::DSL` and `Zr::Reader::Sandbox` are two implementations of
  # one DSL. Both include this one module, so their helpers cannot differ.
  module Fixtures
    ROOT = File.expand_path("../fixtures", __dir__)

    module_function

    # Returns the bytes of `test/fixtures/<name>` as binary. A fixture can
    # contain bytes that are not text. Also, both the spec runner and the
    # reader write it with `File.binwrite`, so a run cannot see an encoding.
    def fixture(name)
      path = File.join(ROOT, name)
      raise ArgumentError, "no fixture at test/fixtures/#{name}" unless File.file?(path)

      File.binread(path)
    end

    # Returns the `files:` hash for fixtures that a program reads through
    # `../../fixtures/`. The path of the program is
    # `<suite>/<area>/<name>.rb`, two directories below the directory it
    # runs in, so the fixtures go there.
    #
    #   files: fixtures("raising_feature/r1.rb", "raising_feature/r2.rb")
    def fixtures(*names)
      names.to_h { |name| ["../../fixtures/#{name}", fixture(name)] }
    end

    # Returns the `files:` hash for the files of the program itself. The
    # program uses the same name as the fixture, so each name occurs once.
    #
    #   files: beside("autoload_nested/lib/greeter.rb", "autoload_nested/main.rb")
    #
    # The program gives the directory name, for example
    # `require_relative "autoload_nested/main"`. If you rename the
    # directory, change the program too, and run `zr-dev oracle` to check it.
    def beside(*names)
      names.to_h { |name| [name, fixture(name)] }
    end
  end
end
