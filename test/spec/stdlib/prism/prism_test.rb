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
end
