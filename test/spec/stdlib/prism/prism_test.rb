# frozen_string_literal: true

require "spec_helper"

describe "Prism programs" do
  it "prism parses ruby natively" do
    result = ze0(<<~'RUBY')
      # native only: a program that requires prism carries the compiler, which the wasm road does not build
      # prism, the parser ruby itself uses: its Ruby half over ze0's Ruby port of
      # its C, compiled into the binary like any other Ruby.

      require "prism"
      puts Prism::VERSION
      result = Prism.parse("x = 1 + 2\nputs x")
      puts result.success?
      puts result.value.class
      body = result.value.statements.body
      puts body.map { |node| node.class.name }.inspect
      puts body.first.name.inspect
      puts result.value.locals.inspect
      bad = Prism.parse("def")
      puts bad.success?
      puts bad.errors.first.message
      puts Prism.parse_success?("1 + 1")
      puts Prism.parse_failure?("1 +")
      puts Prism.lex("a b").value.map { |token, | token.type }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      1.9.0
      true
      Prism::ProgramNode
      ["Prism::LocalVariableWriteNode", "Prism::CallNode"]
      :x
      [:x]
      false
      unexpected end-of-input; expected a method name
      true
      true
      [:IDENTIFIER, :IDENTIFIER, :EOF]
    OUT
  end

  it "store prism gem takes the ffi road" do
    result = ze0(<<~'RUBY', env: {"ZEO_DISABLE_BUILTIN" => "prism"})
      # `require "prism"` out of the gem store reaches `prism/ffi.rb` even though
      # zeo builds and loads the gem's C extension: the DEBUG log shows
      # `load C extension .../ext/prism/prism.bundle`, and `Prism.parse` still
      # raises `uninitialized constant Prism::LibRubyParser::PrismString`.
      #
      # `prism` is the one gem in the C-API sweep with two backends, and its
      # loader picks between them with `RUBY_ENGINE == "ruby"`, which zeo answers
      # `"ruby"`. Recorded as a note; `crates/zeo/tests/fixtures/capi_sweep/
      # XFAIL.json` carries the same finding for the sweep.


      require "prism"

      r = Prism.parse("1 + 2\n")
      puts r.success?, r.value.class
      puts Prism::VERSION
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Prism::ProgramNode
      1.9.0
    OUT
  end
end
