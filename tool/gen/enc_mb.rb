# frozen_string_literal: true

require_relative "../gen"
require_relative "../../test/support/harness/onig"

module Zr
  module Dev
    module Commands
      class Gen
        # Writes lib/zr/runtime/kernel/enc_mb.rb, which the runtime uses to walk a
        # String in a multibyte encoding. It comes from the Onigmo encoders that
        # Regexp uses (lib/zr/runtime/core/regexp/onig/encoding_multibyte.rb). Thus a
        # String and a Regexp agree on every character: both read the lead-byte
        # lengths and state tables of CRuby's enc/*.c, through the descriptor
        # that the matcher uses.
        #
        #   zr-dev gen enc_mb
        #
        # First, the task checks the descriptors against ruby: every one-byte
        # and two-byte sequence, and a sample of longer ones, must be valid only
        # where String#valid_encoding? returns true.
        class EncMb < Generator
          host_ruby!
          writes "lib/zr/runtime/kernel/enc_mb.rb"

          # Onigmo's encoders. They exist only after the port is loaded.
          def encoders = Regexp::Onig::Enc

          def index_of(encoding) = Encoding.list.index(encoding)

          # Whether the bytes are one whole character, by the precise_mbc_enc_len
          # of the encoder that the descriptor comes from.
          def found?(enc, bytes)
            n = enc.precise_len(bytes, 0, bytes.bytesize)
            n == bytes.bytesize
          end

          def ranges(list)
            out = []
            list.sort.each do |n|
              if out.last && out.last[1] == n - 1
                out.last[1] = n
              else
                out << [n, n]
              end
            end
            out
          end

          def test(name, list)
            ranges(list).map { |from, to| from == to ? "#{name} == #{from}" : "#{name} >= #{from} && #{name} <= #{to}" }.join(" || ")
          end

          def def_name(enc) = "zr_enc_mb_#{enc.name.downcase.tr("-", "_")}"

          def write(io)
            require_relative "../../lib/zr/runtime"

            Zr::Harness::Onig.load!

            # The encodings that need their own encoder to walk a String: they
            # are ASCII-compatible, a character can have more than one byte, and
            # they are not UTF-8 with a different name.
            readers = Encoding.list.reject(&:dummy?).select(&:ascii_compatible?)
            utf8_like = readers.select { |encoding| encoding != Encoding::UTF_8 && Regexp::Onig::EncTables::BASES[encoding.name] == "UTF-8" }
            mb = (readers - utf8_like).select { |encoding| encoders.for(encoding).max_len > 1 && encoding != Encoding::UTF_8 }
            bases = mb.group_by { |encoding| encoders.for(encoding) }

            random = Random.new(1)
            bases.each do |enc, encodings|
              encodings.each do |encoding|
                sequences = (0x80..0xFF).zip
                sequences += (0x80..0xFF).flat_map { |a| (0..0xFF).map { |b| [a, b] } }
                byte = -> { random.rand(3).zero? ? random.rand(0x30..0x39) : random.rand(0x80..0xFF) }
                sequences += Array.new(100_000) { Array.new(random.rand(3..6)) { byte.call } }
                sequences.each do |bytes|
                  text = bytes.pack("C*")
                  ours = found?(enc, text.b)
                  theirs = text.dup.force_encoding(encoding).valid_encoding? && text.dup.force_encoding(encoding).length == 1
                  fail! "#{encoding.name} #{text.unpack1("H*")}: ruby says #{theirs}, the descriptor #{ours}" unless ours == theirs
                end
              end
            end

            kernel = +<<~HEAD
              # How to step through a String in a multibyte encoding. `zr-dev gen
              # enc_mb` generates this from the Onigmo encoders that Regexp uses. Each
              # encoding's descriptor (Regexp::Onig::Enc::Base#descriptor) contains the
              # lead-byte lengths and state tables of its enc/*.c file. The matcher's
              # zr_onig_precise_len also reads them, so a String and a Regexp on it
              # find the same characters.

              module Zr::Kern
                # Whether the encoding `index` has multibyte characters of its own
                # kind: not UTF-8, not UTF-16 or UTF-32, and not one byte for each
                # character.
                #: (word) -> bool
                def zr_enc_mb_p(index)
                  #{test("index", mb.map { |e| index_of(e) })}
                end

                # Whether the encoding writes its characters in the same way as UTF-8.
                #: (word) -> bool
                def zr_enc_utf8_like_p(index)
                  #{test("index", utf8_like.map { |e| index_of(e) })}
                end

                # The descriptor to step through a multibyte encoding, or 0 for other
                # encodings.
                #: (word) -> word
                def zr_enc_mb_descriptor(index)
            HEAD
            blobs = bases.group_by { |enc, _| enc.descriptor }.to_h { |_, pairs| [pairs.first.first, pairs.flat_map(&:last)] }
            blobs.each do |enc, encodings|
              kernel << "    # #{encodings.map(&:name).join(", ")}\n"
              kernel << "    if #{test("index", encodings.map { |e| index_of(e) })}\n"
              kernel << "      return Machine.word(#{def_name(enc)})\n    end\n"
            end
            kernel << "    0\n  end\n"
            # The later lines of a bytes literal are inside the String, so
            # they have no indent.
            blobs.each_key do |enc|
              kernel << "\n  #: () -> ptr\n  def #{def_name(enc)}\n"
              kernel << "    Machine.bytes(\n    #{bytes_literal(enc.descriptor.bytes)})\n  end\n"
            end
            kernel << "end\n"
            io.print kernel
            warn "#{blobs.size} descriptors for #{mb.size} encodings, #{kernel.bytesize} bytes"
          end
        end
      end
    end
  end
end
