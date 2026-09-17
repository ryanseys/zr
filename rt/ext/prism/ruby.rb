# frozen_string_literal: true

# prism's parser in Ruby: a port of prism 1.9.0's C (src/prism.c and its
# helpers), which rt/ext/prism.so.rb stands on in place of the C extension.
# prism is MIT licensed; see vendor/ext/prism/LICENSE.md.
require_relative "ruby/parser"
require_relative "ruby/format"
require_relative "ruby/token_lexers"
require_relative "ruby/escapes"
require_relative "ruby/magic_comments"
require_relative "ruby/lexer"
require_relative "ruby/lex_modes"

module Prism
  module Ruby
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
