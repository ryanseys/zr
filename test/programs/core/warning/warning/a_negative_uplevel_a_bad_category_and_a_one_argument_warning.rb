def t(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end
t(1) { warn "x", uplevel: -1 }
t(2) { warn "x", category: 5 }
t(3) { Warning.warn("x", category: "deprecated") }
t(4) { Warning[:deprecated] = :yes }
t(5) { Warning[:deprecated] }
t(6) { Warning.warn("x".encode("UTF-16LE")) }
module Warning
  def self.warn(message) = print("ONE #{message}")
end
t(7) { warn "arity one", category: :experimental }
