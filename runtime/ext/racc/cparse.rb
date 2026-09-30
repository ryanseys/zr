# frozen_string_literal: false

# racc's cparse.c, in ruby: the parser core that `require "racc/cparse"`
# loads from racc/parser.rb. The C core and racc's own Ruby core
# (Racc::Parser#_racc_do_parse_rb, in the same parser.rb) run the same
# tables to the same result, so the two entry points here call the Ruby
# core. What the C extension defines is here, so a program sees the
# names that ruby's racc has: Racc::CparseParams, the C core's version,
# and the parser's `c` runtime type.
module Racc
  # The state of one C parse. The C keeps it in a typed object that only
  # the core makes; a program cannot make one.
  class CparseParams
    Primitive.zr_undef_allocator(self)
  end

  class Parser
    # The C core is the gem's own, so it has the gem's version. The C
    # makes both strings with rb_str_new, so neither is frozen.
    Racc_Runtime_Core_Version_C = ::Racc::VERSION.dup
    Racc_Runtime_Core_Id_C = "$originalId: cparse.c,v 1.8 2006/07/06 11:39:46 aamine Exp $"

    private

    def _racc_do_parse_c(arg, sysdebug) = _racc_do_parse_rb(arg, sysdebug)

    def _racc_yyparse_c(lexer, lexmid, arg, sysdebug) = _racc_yyparse_rb(lexer, lexmid, arg, sysdebug)
  end
end
