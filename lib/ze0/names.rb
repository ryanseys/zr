# frozen_string_literal: true

module Ze0
  # Symbol spellings, matching crates/zeo/src/names.rs and clif/names.rs so
  # a program ze0 writes names the same functions the Rust emitter would.
  module Names
    TOPLEVEL = "zeo_toplevel"

    # A Ruby name as an identifier fragment: every character an identifier
    # grammar refuses becomes its `_uXXXX_` code point, reversibly.
    def self.fragment(name)
      name = name.to_s
      out = +""
      name.each_char.with_index do |c, i|
        ok = c == "_" || (i.zero? ? c.match?(/\A[\p{XID_Start}]\z/) : c.match?(/\A[\p{XID_Continue}]\z/))
        out << (ok ? c : format("_u%04X_", c.ord))
      end
      out
    end

    def self.method_symbol(name)
      "zeo_m_Object_#{fragment(name)}"
    end

    def self.trampoline_symbol(name)
      "zeo_t_Object_#{fragment(name)}"
    end

    # The frame label of a top-level `def`.
    def self.method_label(name)
      "Object##{name}"
    end
  end
end
