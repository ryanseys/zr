# syntax_suggest loads, with the hook that ruby's error display calls.
require "syntax_suggest"
p SyntaxSuggest.respond_to?(:handle_error)
