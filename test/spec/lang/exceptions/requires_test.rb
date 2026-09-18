# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: loading files" do
  it "cwd require that misses raises at runtime" do
    result = ze0(<<~'RUBY')
      # `require "./x"` resolves against the runtime working directory in real
      # Ruby. zeo resolves it against the requiring file's directory (the
      # deterministic analogue -- `load`'s documented rule), and a MISS defers to
      # a catchable runtime `LoadError` instead of refusing to compile: the gems
      # that write this shape only ever worked when run from the directory the
      # path assumes, and wrap it in a rescue for everywhere else.
      begin
        require "./tools/not_shipped_here"
      rescue LoadError => e
        puts "caught: #{e.class}"
      end

      begin
        require "~/nothing_under_home_either"
      rescue LoadError => e
        puts "caught: #{e.class}"
      end

      puts "still compiling"
    RUBY

    _(result).must_answer <<~'OUT'
      caught: LoadError
      caught: LoadError
      still compiling
    OUT
  end

  it "did you mean library" do
    result = ze0(<<~'RUBY')
      # did_you_mean is loaded before the program, as ruby's gem prelude loads
      # it, and a NameError names the locals and methods it may have meant.
      p require("did_you_mean")
      p defined?(DidYouMean)
      p DidYouMean::SpellChecker.new(dictionary: %w[length size]).correct("lenght")
      first_name = "x"
      begin
        frist_name
      rescue NameError => e
        puts e.detailed_message(highlight: false)
      end

    RUBY

    _(result).must_answer "false\n\"constant\"\n[\"length\"]\nundefined local variable or method 'frist_name' for main (NameError)\n\n  frist_name\n  ^^^^^^^^^^\nDid you mean?  first_name\n"
  end

  it "load error path" do
    result = ze0(<<~'RUBY')
      # `LoadError#path` names the feature that would not load. It is one of the
      # typed introspection slots an exception carries beside its message, and the
      # raise site fills it; a hand-built LoadError leaves it nil rather than raising
      # the way an unset `KeyError#key` does.
      begin
        require "definitely_not_a_gem"
      rescue LoadError => e
        p e.path
        p e.message
      end

      p LoadError.new("hand built").path
      p LoadError.new.path
      p LoadError.instance_method(:path).owner
      p LoadError.new("x").respond_to?(:path)

      # A subclass inherits the reader, and a raise through it fills the same slot.
      class VendorMissing < LoadError; end
      p VendorMissing.new("nope").path
      begin
        raise VendorMissing, "no vendor"
      rescue LoadError => e
        p [e.class, e.path]
      end

      # `load` of a missing file records its argument too.
      begin
        load "no/such/script.rb"
      rescue LoadError => e
        p e.path
      end

      # The slot is hidden, like the message slot -- it is not an ivar.
      begin
        require "another_missing_one"
      rescue LoadError => e
        p e.instance_variables
      end

      # A sibling ScriptError has no `#path`.
      p NotImplementedError.new("x").respond_to?(:path)
      p ArgumentError.new("x").respond_to?(:path)
    RUBY

    _(result).must_answer <<~'OUT'
      "definitely_not_a_gem"
      "cannot load such file -- definitely_not_a_gem"
      nil
      nil
      LoadError
      true
      nil
      [VendorMissing, nil]
      "no/such/script.rb"
      [:@path]
      false
      false
    OUT
  end

  it "require gated extension constant is a name error without its require" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/require_gated_extension_constant_is_a_name_error_without_its_require.rb")
      # The ext require-gate: a require-gated builtin's constant
      # (`Base64`, gated by `"base64"`) is INVISIBLE until `require "base64"`
      # activates it -- referencing it un-required raises `NameError:
      # uninitialized constant Base64`, oracle-verified against ruby 4.0.6
      # (`uninitialized constant Base64 (NameError)`). The gate rides the
      # ordinary `resolve_class` -> unset-constant path, so it's a rescuable
      # RUNTIME NameError, not a compile error.

      puts Base64.strict_encode64("hi")
    RUBY

    _(result).must_answer "", stderr: "lang/exceptions/require_gated_extension_constant_is_a_name_error_without_its_require.rb:9:in '<main>': uninitialized constant Base64 (NameError)\n\nputs Base64.strict_encode64(\"hi\")\n     ^^^^^^\n", status: 1
  end

  it "require gated extension name error is rescuable" do
    result = ze0(<<~'RUBY')
      # Same gate, caught: since the miss surfaces through the runtime
      # constant path it's an ordinary rescuable `NameError` (oracle prints
      # `rescued: uninitialized constant Base64`). This program NEVER requires
      # base64, so activation stays off -- avoiding the documented
      # program-global-activation divergence (a `require` anywhere activates
      # the constant everywhere, unlike CRuby's file-ordered visibility).

      begin
        Base64.strict_encode64("hi")
      rescue NameError => e
        puts "rescued: #{e.message}"
      end
    RUBY

    _(result).must_answer "rescued: uninitialized constant Base64\n"
  end

  it "require that cannot resolve takes the rescue" do
    result = ze0(<<~'RUBY')
      # The i18n/excon shape: an optional accelerator behind `begin; require "x";
      # <definitions>; rescue LoadError; <fallback>`. The feature does not exist, so
      # ruby raises at the require and only the fallback ever runs.

      module Codec
        begin
          require "an_accelerator_that_is_not_installed"

          class Backend
            def self.name
              "native"
            end
          end
        rescue LoadError
          class Backend
            def self.name
              "pure ruby"
            end
          end
        end
      end

      puts Codec::Backend.name
      puts defined?(Codec::Backend)
    RUBY

    _(result).must_answer <<~'OUT'
      pure ruby
      constant
    OUT
  end

  it "require that raises is rescuable" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_require_that_raises_is_rescuable.rb", files: fixtures("raising_feature/ok.rb", "raising_feature/r7.rb", "raising_feature/r1.rb", "raising_feature/r2.rb", "raising_feature/r3.rb", "raising_feature/r4.rb", "raising_feature/r5.rb", "raising_feature/r6.rb", "raising_feature/r8.rb"))
      # A `require` zeo resolves at COMPILE time is spliced in place, and the
      # spliced body has to land INSIDE the `begin` that wrote the require. CRuby
      # runs the required file during the `require` call, so a raise from the
      # file's top level both reaches the handler around it and aborts the rest of
      # the begin's body.
      #
      # zeo spliced it out as a SIBLING, and broke both halves: the program died
      # where ruby rescues, and the statements after the require ran anyway. It was
      # hidden because a require zeo CANNOT resolve statically takes the run-time
      # path, which was always rescuable.
      #
      # `begin; require "optional"; rescue LoadError; end` is the everyday shape.

      $LOAD_PATH.unshift(File.expand_path("../../fixtures/raising_feature", __dir__))

      begin
        require "r1"
        puts "after require -- must not print"
      rescue => e
        puts "bare rescue        #{e.class}: #{e.message}"
      end

      begin
        require "r2"
      rescue ArgumentError
        puts "named rescue       ok"
      ensure
        puts "ensure             ran"
      end

      # Nothing raises: the `else` runs and the handler stays dead.
      begin
        require_relative "../../fixtures/raising_feature/ok"
        puts "body finished      #{LOADED_CLEANLY}"
      rescue ArgumentError
        puts "must not run"
      else
        puts "else               ran"
      end

      begin
        require "r3"
      rescue TypeError
        puts "must not run"
      rescue ArgumentError
        puts "second clause      ok"
      end

      begin
        begin
          require "r4"
        rescue ArgumentError
          puts "inner rescue       ok"
        end
      rescue Exception
        puts "outer must not run"
      end

      # A method-body require runs when the method does, not at load.
      def load_r5
        require "r5"
      rescue ArgumentError => e
        "method rescued: #{e.message}"
      end
      puts "method body        #{load_r5}"

      # The begin is an EXPRESSION: the handler's value is the begin's value.
      value = begin
        require "r6"
        "no raise"
      rescue ArgumentError
        "value from rescue"
      end
      puts "as an expression   #{value}"

      # `require_relative` and `load` take the same path.
      begin
        require_relative "../../fixtures/raising_feature/r7"
      rescue ArgumentError => e
        puts "require_relative   #{e.message}"
      end

      begin
        load File.expand_path("../../fixtures/raising_feature/r8.rb", __dir__)
      rescue ArgumentError => e
        puts "load               #{e.message}"
      end

      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      bare rescue        ArgumentError: raise from r1
      named rescue       ok
      ensure             ran
      body finished      true
      else               ran
      second clause      ok
      inner rescue       ok
      method body        method rescued: raise from r5
      as an expression   value from rescue
      require_relative   raise from r7
      load               raise from r8
      still running
    OUT
  end

  it "rescued require load error" do
    result = ze0(<<~'RUBY', files: {"rescued_require_load_error/probe.rb" => "# The power_assert shape: a load-time probe that raises LoadError before any\n# definitions, so the file contributes nothing when the probe fails.\nraise LoadError, \"probe says no\"\nGOOD = 1\n"})
      # A require inside `begin ... rescue LoadError` whose FILE RESOLVES but whose
      # top level RAISES LoadError when it runs -- power_assert's TracePoint probe,
      # which test-unit requires exactly this way and degrades by rescuing. The
      # spliced statements sit inside a synthesized begin carrying the written
      # rescue clauses, so the raise lands in the handler CRuby's require timing
      # would give it, and execution continues after the begin.
      begin
        require_relative "rescued_require_load_error/probe"
      rescue LoadError => e
        p e.message
      end
      p :after
    RUBY

    _(result).must_answer <<~'OUT'
      "probe says no"
      :after
    OUT
  end

  it "unresolvable require inside rescue loaderror defers to runtime" do
    result = ze0(<<~'RUBY')
      # The optional-dependency idiom: `begin; require 'missing'; rescue
      # LoadError`. A literal require that can't be resolved but is lexically
      # inside a `rescue LoadError` is deferred to a runtime `Kernel#require`
      # (raising the LoadError the rescue handles), not a loud compile error.
      # net/http's `begin; require 'win32/sspi'; rescue LoadError` needs this.

      begin
        require "definitely_missing_optdep_xyz"
        puts "loaded"
      rescue LoadError => e
        puts "rescued: #{e.send(:message)}"
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      rescued: cannot load such file -- definitely_missing_optdep_xyz
      after
    OUT
  end
end
