# frozen_string_literal: true

require_relative "../../../runtime_sources"

module Zr
  module Machine
    class Host
      class Walk
        # Regexp compiles on the host. The core's own compiler
        # (lib/zr/runtime/core/regexp/onig, regexp_pattern.rb) is plain Ruby,
        # so CRuby runs it here at its own speed, where the walker would
        # take minutes for a library's patterns (`require "uri"`). The core
        # asks for each compile through `zr_regexp_host_compile`
        # (`Regexp.compiled`); a binary's kernel answers nil, and the core
        # compiles the pattern itself.
        module Regexps
          FILES = [*RuntimeSources::ONIG_NAMES, "regexp_pattern"].map { |name| File.join(Paths::RUNTIME, "core/#{name}.rb") }.freeze

          # The compile of the String Value `source` under the fixnum Value
          # `bits`, as the Value [encoding index, bits, program, name rows,
          # warning rows]. When CRuby refuses the pattern, nil: the core
          # compiles it again and raises the error.
          def regexp_compile(source, bits)
            FILES.each { |file| require file }
            text = Memory.read(k::RString.ptr(source), k::RString.len(source))
            text.force_encoding(::Encoding.list.fetch(k.zr_str_encoding_index(source)))
            # The core keeps both names private in Regexp.
            encoding, bits, compiled, warnings = ::Regexp.const_get(:Pattern).compile(text.freeze, bits >> 1)
            names = compiled.name_table.to_a.map { |name, entry| [name.b, entry.back_refs] }
            value([::Encoding.list.index(encoding), bits, ::Regexp.const_get(:Onig)::Program.pack(compiled), names,
                   warnings.rows.map { |row| [row.verbose, row.text.b] }])
          rescue ::RegexpError, ::ArgumentError, ::EncodingError
            @qnil
          end
        end
      end
    end
  end
end
