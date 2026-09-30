# frozen_string_literal: true
# shareable_constant_value: literal

# prism's parser in Ruby: a port of prism 1.9.0's C (src/prism.c and its
# helpers), which runtime/ext/prism/prism.rb uses in place of the C extension.
# prism is MIT licensed; see vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0/LICENSE.md.
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
require_relative "ruby/ast"
require_relative "ruby/extension"
require_relative "ruby/string_query"
require_relative "ruby/pack"
