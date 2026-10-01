# Regexp::Onig: Onigmo, the regular expression engine of CRuby 4.0.7,
# in Ruby. The parser, the tree setup, the optimizer and the compiler
# live here in plain Ruby; the matcher is the kernel's (lib/zr/runtime/kernel/onig_*.rb).
#
# Onigmo is Copyright (c) 2002-2013 K.Kosako and 2011-2016 K.Takata,
# under the BSD-2-Clause license reproduced in lib/zr/runtime/core/regexp.rb. This
# is an altered version: the same algorithms in Ruby.
#
# The files also load under CRuby (test/support/harness/onig.rb), so
# tools/regexp_diff.rb and the tests can check them against ruby's own
# engine on the host.

class Regexp
  module Onig
    STACK_POP_LEVEL_FREE = 0
    STACK_POP_LEVEL_MEM_START = 1
    STACK_POP_LEVEL_ALL = 2

    # The tree of `pattern` (bytes) under `options`, as [root, reg,
    # warnings]. `enc` is an Enc encoding (Enc.for).
    def self.parse(pattern, options, enc)
      reg = Reg.new(options | Syntax::RUBY_OPTIONS, enc)
      warnings = Warnings.new
      root = Parser.new(reg, pattern, warnings).parse_make_tree
      [root, reg, warnings]
    end

    # onig_reg_init: the options a pattern compiles under, with the
    # syntax's defaults.
    def self.reg_init(option, enc)
      if (option & (Option::DONT_CAPTURE_GROUP | Option::CAPTURE_GROUP)) == (Option::DONT_CAPTURE_GROUP | Option::CAPTURE_GROUP)
        raise Error.new(Err::INVALID_COMBINATION_OF_OPTIONS)
      end

      if (option & Option::NEGATE_SINGLELINE) != 0
        option |= Syntax::RUBY_OPTIONS
        option &= ~Option::SINGLELINE
      else
        option |= Syntax::RUBY_OPTIONS
      end
      Reg.new(option, enc)
    end

    # onig_compile: `pattern` (bytes) compiled under `option` for `enc`;
    # [reg, warnings], the reg holding the byte code and the search
    # information. Raises Onig::Error as onig_new fails.
    def self.compile(pattern, option, enc)
      reg = reg_init(option, enc)
      warnings = Warnings.new
      pattern = pattern.b
      parser = Parser.new(reg, pattern, warnings)
      scan_env = parser.env
      root = parser.parse_make_tree

      # mixed use named group and no-named group
      if scan_env.num_named > 0 && Syntax.bv?(Syntax::CAPTURE_ONLY_NAMED_GROUP) && (reg.options & Option::CAPTURE_GROUP) == 0
        if scan_env.num_named != scan_env.num_mem
          root = Tune.disable_noname_group_capture(root, reg, scan_env)
        else
          Tune.numbered_ref_check(root)
        end
      end

      uslist = nil
      if scan_env.num_call > 0
        uslist = []
        scan_env.unset_addr_list = uslist
        Tune.setup_subexp_call(root, scan_env)
        Tune.subexp_recursive_check_trav(root, scan_env)
        Tune.subexp_inf_recursive_check_trav(root, scan_env)
        reg.num_call = scan_env.num_call
      else
        reg.num_call = 0
      end

      Tune.setup_tree(root, reg, 0, scan_env)

      reg.capture_history = scan_env.capture_history
      reg.bt_mem_start = scan_env.bt_mem_start | reg.capture_history
      if (reg.options & (Option::FIND_LONGEST | Option::FIND_NOT_EMPTY)) != 0
        reg.bt_mem_end = 0xffffffff
      else
        reg.bt_mem_end = scan_env.bt_mem_end | reg.capture_history
      end

      Optimize.clear_info(reg)
      Optimize.set_info_from_tree(root, reg, scan_env)

      reg.code = Code.new
      compiler = Compiler.new(reg)
      compiler.compile_tree(root)
      reg.code.add_opcode(Op::END_)
      compiler.fix_unset_addrs(uslist) unless uslist.nil?

      reg.stack_pop_level = if reg.num_repeat != 0 || reg.bt_mem_end != 0
                              STACK_POP_LEVEL_ALL
                            elsif reg.bt_mem_start != 0
                              STACK_POP_LEVEL_MEM_START
                            else
                              STACK_POP_LEVEL_FREE
                            end
      reg.tree = root
      [reg, warnings]
    end
  end
end
