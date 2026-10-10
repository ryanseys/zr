# frozen_string_literal: true

# A tree in the shape of Onigmo's print_indent_tree (regcomp.c, under
# ONIG_DEBUG_PARSE_TREE), for the tests and for reading a parse.
class Regexp
  module Onig
    module Dump
      ENCLOSE_NAMES = { Enclose::OPTION => "option", Enclose::MEMORY => "memory",
                        Enclose::STOP_BACKTRACK => "stop-bt", Enclose::CONDITION => "condition",
                        Enclose::ABSENT => "absent" }.freeze
      ANCHOR_NAMES = { Anchor::BEGIN_BUF => "begin buf", Anchor::END_BUF => "end buf",
                       Anchor::BEGIN_LINE => "begin line", Anchor::END_LINE => "end line",
                       Anchor::SEMI_END_BUF => "semi end buf", Anchor::BEGIN_POSITION => "begin position",
                       Anchor::WORD_BOUND => "word bound", Anchor::NOT_WORD_BOUND => "not word bound",
                       Anchor::WORD_BEGIN => "word begin", Anchor::WORD_END => "word end",
                       Anchor::PREC_READ => "prec read", Anchor::PREC_READ_NOT => "prec read not",
                       Anchor::LOOK_BEHIND => "look_behind", Anchor::LOOK_BEHIND_NOT => "look_behind_not",
                       Anchor::KEEP => "keep" }.freeze
      CTYPE_NAMES = { CType::WORD => "word" }.freeze

      def self.tree(node, indent = 0, out = +"")
        pad = " " * indent
        if node.nil?
          out << "#{pad}<nil>\n"
          return out
        end
        case node.ntype
        when Node::LIST, Node::ALT
          out << "#{pad}<#{node.ntype == Node::LIST ? "list" : "alt"}:#{id(node)}>\n"
          n = node
          until n.nil?
            tree(n.car, indent + 2, out)
            n = n.cdr
          end
        when Node::STR
          kind = node.str_raw? ? "str-raw" : "str"
          kind += "-ambig" if node.str_ambig?
          out << "#{pad}<#{kind}:#{id(node)}>"
          node.s.each_byte { |b| out << (b >= 0x20 && b < 0x7f ? b.chr : format("\\x%02x", b)) }
          out << "\n"
        when Node::CCLASS
          out << "#{pad}<cclass:#{id(node)}>"
          out << " not" if node.cclass_not?
          out << " bs:#{bitset_text(node.bs)}"
          unless node.mbuf.nil?
            pairs = node.mbuf.each_slice(2).map { |lo, hi| format("%04x-%04x", lo, hi) }; out << " mbuf(#{pairs.size}):" + (pairs.size > 6 ? (pairs.first(3) + ["..."] + pairs.last(2)).join(",") : pairs.join(","))
          end
          out << "\n"
        when Node::CTYPE
          out << "#{pad}<ctype:#{id(node)}> #{node.not ? "not " : ""}#{CTYPE_NAMES.fetch(node.ctype, node.ctype)}#{node.ascii_range ? "(ascii)" : ""}\n"
        when Node::CANY
          out << "#{pad}<anychar:#{id(node)}>\n"
        when Node::ANCHOR
          out << "#{pad}<anchor:#{id(node)}> #{ANCHOR_NAMES.fetch(node.type, node.type)}#{node.ascii_range ? "(ascii)" : ""}\n"
          tree(node.target, indent + 2, out) unless node.target.nil?
        when Node::BREF
          out << "#{pad}<backref:#{id(node)}>#{node.backs.join(",")}"
          out << " level:#{node.nest_level}" if node.status?(Status::NEST_LEVEL)
          out << "\n"
        when Node::CALL
          out << "#{pad}<call:#{id(node)}>#{node.name.inspect}#{node.group_num}\n"
        when Node::QTFR
          out << "#{pad}<quantifier:#{id(node)}>{#{node.lower},#{node.upper == REPEAT_INFINITE ? "*" : node.upper}}#{node.greedy ? "" : "?"}\n"
          tree(node.target, indent + 2, out)
        when Node::ENCLOSE
          out << "#{pad}<enclose:#{id(node)}> #{ENCLOSE_NAMES.fetch(node.type, node.type)}"
          out << ":#{node.regnum}" if node.type == Enclose::MEMORY || node.type == Enclose::CONDITION
          out << ":#{format("%x", node.option)}" if node.type == Enclose::OPTION
          out << "\n"
          tree(node.target, indent + 2, out)
        else
          out << "#{pad}<unknown #{node.ntype}>\n"
        end
        out
      end

      # Nodes are named by their order of appearance, not their address.
      def self.id(_node) = ""

      def self.bitset_text(bs)
        runs = []
        i = 0
        while i < 256
          if BitSet.at?(bs, i)
            j = i
            j += 1 while j < 256 && BitSet.at?(bs, j)
            runs << (j - 1 == i ? format("%02x", i) : format("%02x-%02x", i, j - 1))
            i = j
          else
            i += 1
          end
        end
        runs.empty? ? "-" : runs.join(",")
      end
    end
  end
end
