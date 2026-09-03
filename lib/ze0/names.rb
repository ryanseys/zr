# frozen_string_literal: true

module Ze0
  # Symbol spellings, matching crates/zeo/src/names.rs and clif/names.rs so
  # a program ze0 writes names the same functions the Rust emitter would.
  module Names
    TOPLEVEL = "zeo_toplevel"
    # The owner of a top-level `def`.
    OBJECT = "Object"

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

    # A fully-qualified owner (`Outer::Inner`) as a symbol fragment. The
    # owner is already an identifier but for its separator.
    def self.owner_fragment(owner)
      owner.to_s.gsub("::", "__")
    end

    # The four channels a method body reaches the runtime through: an
    # instance method's body and its `ValueFn` trampoline, and the same
    # pair for a class method.
    def self.method_symbol(owner, name)
      "zeo_m_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    def self.trampoline_symbol(owner, name)
      "zeo_t_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    def self.class_method_symbol(owner, name)
      "zeo_cm_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    def self.class_trampoline_symbol(owner, name)
      "zeo_ct_#{owner_fragment(owner)}_#{fragment(name)}"
    end

    # The frame labels a backtrace prints: an instance method, a class
    # method, and a class or module body.
    def self.method_label(owner, name)
      "#{owner}##{name}"
    end

    def self.class_method_label(owner, name)
      "#{owner}.#{name}"
    end

    def self.body_label(owner, kind)
      "<#{kind}:#{owner}>"
    end
  end
end
