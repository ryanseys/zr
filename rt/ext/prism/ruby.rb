# frozen_string_literal: true

# prism's parser in Ruby: a port of prism 1.9.0's C (src/prism.c and its
# helpers), which rt/ext/prism.so.rb stands on in place of the C extension.
# prism is MIT licensed; see vendor/ext/prism/LICENSE.md.
require_relative "ruby/parser"
require_relative "ruby/mutation"
require_relative "ruby/dump"
require_relative "ruby/format"
require_relative "ruby/token_lexers"
require_relative "ruby/escapes"
require_relative "ruby/magic_comments"
require_relative "ruby/lexer"
require_relative "ruby/lex_modes"
require_relative "ruby/nodes"
require_relative "ruby/static_literals"
require_relative "ruby/regexp"
require_relative "ruby/parser/core"
require_relative "ruby/parser/blocks"
require_relative "ruby/parser/strings"
require_relative "ruby/parser/patterns"
require_relative "ruby/parser/prefix"
require_relative "ruby/parser/infix"
require_relative "ruby/result"

module Prism
  module Ruby
    # Prism.parse's steps in Ruby: `[result, facts]`, where the facts are
    # what Dump.parse needs beside the result to write Prism.dump's bytes.
    def self.parse(source, **options)
      Parser.new(source, Options.new(**options)).parse
    end

    # Prism.dump in Ruby.
    def self.dump(source, **options)
      result, facts = parse(source, **options)
      Dump.parse(result, **facts)
    end

    # The tokens of a source as the lex callback sees them, with no parser
    # behind the lexer: `[type, start, length, lex_state]` each, the last one
    # EOF. Tokens whose kind the parser decides differ from Prism.lex's.
    def self.lex_tokens(source, **options)
      parser = Parser.new(source, Options.new(**options))
      tokens = []
      parser.instance_variable_set(:@lex_callback, ->(type, start, finish, state) { tokens << [type, start, finish - start, state] })
      parser.send(:scope_push, parser.instance_variable_get(:@current_scope).nil?)
      loop do
        parser.send(:lex)
        break if parser.instance_variable_get(:@current_type) == :EOF
      end
      tokens
    end
  end
end
