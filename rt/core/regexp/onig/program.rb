# The compiled pattern as the kernel's matcher reads it: one binary
# String holding a header of 64-bit little-endian words, the byte code
# (Onigmo's own layout, ending in OP_END and then OP_FINISH as the
# bottom-of-stack code), the repeat ranges, the exact bytes of the
# optimizer, its byte map and the encoding's descriptor
# (Enc::Base#descriptor). The header's field order is the kernel's
# `Machine.struct :OnigProg` (rt/kernel/onig_match.rb) and nothing else
# reads it.
class Regexp
  module Onig
    module Program
      FIELDS = %i[
        magic enc_off options num_mem num_repeat num_null_check num_call
        bt_mem_start bt_mem_end pop_level code_off code_len repeat_off
        optimize threshold_len anchor sub_anchor anchor_dmin anchor_dmax
        dmin dmax exact_off exact_len map_off case_fold_flag
      ].freeze
      HEADER_SIZE = FIELDS.size * 8
      MAGIC = 0x3067696e4f # "Onig0" little-endian
      # ONIG_INFINITE_DISTANCE as the kernel holds it: a signed word that
      # no real distance reaches, so signed comparisons stay valid.
      INFINITE = 1 << 62

      # The program of a compiled `reg`.
      def self.pack(reg)
        code = reg.code.bytes + Op::FINISH.chr
        repeat_off = align(HEADER_SIZE + code.bytesize)
        repeats = reg.repeat_range.map { |lower, upper| [lower, upper].pack("q<q<") }.join
        exact_off = repeat_off + repeats.bytesize
        exact = reg.exact || "".b
        map_off = align(exact_off + exact.bytesize)
        enc_off = map_off + 256
        header = {
          magic: MAGIC,
          enc_off: enc_off,
          options: reg.options,
          num_mem: reg.num_mem,
          num_repeat: reg.num_repeat,
          num_null_check: reg.num_null_check,
          num_call: reg.num_call,
          bt_mem_start: reg.bt_mem_start,
          bt_mem_end: reg.bt_mem_end,
          pop_level: reg.stack_pop_level,
          code_off: HEADER_SIZE,
          code_len: code.bytesize,
          repeat_off: repeat_off,
          optimize: reg.optimize,
          threshold_len: reg.threshold_len,
          anchor: reg.anchor,
          sub_anchor: reg.sub_anchor,
          anchor_dmin: distance(reg.anchor_dmin),
          anchor_dmax: distance(reg.anchor_dmax),
          dmin: distance(reg.dmin),
          dmax: distance(reg.dmax),
          exact_off: exact_off,
          exact_len: exact.bytesize,
          map_off: map_off,
          case_fold_flag: reg.case_fold_flag,
        }
        out = FIELDS.map { |f| header.fetch(f) }.pack("q<*")
        out << code
        out << "\0".b * (repeat_off - out.bytesize)
        out << repeats
        out << exact
        out << "\0".b * (map_off - out.bytesize)
        out << (reg.map ? reg.map.pack("C*") : "\0".b * 256)
        out << reg.enc.descriptor
        out.freeze
      end

      def self.distance(d) = d == INFINITE_DISTANCE ? INFINITE : d
      def self.align(n) = (n + 7) & ~7
    end
  end
end
