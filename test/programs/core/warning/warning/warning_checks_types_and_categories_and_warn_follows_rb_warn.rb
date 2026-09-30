$stderr = $stdout
def t(l) = (r = yield; puts "#{l}: #{r.inspect}") rescue puts("#{l}: #{$!.class}: #{$!.message}")
t(1) { Warning[:deprecated] = 1 }
t(2) { Warning[:deprecated] = nil; Warning[:deprecated] }
t(3) { Warning["deprecated"] }
t(4) { warn "x", category: "deprecated" }
t(5) { warn "x", category: nil }
t(6) { Warning[:performance] = true; warn "perf", category: :performance }
t(7) { warn "a\n", "b" }
t(8) { warn "q", uplevel: 1 }
t(9) { def w9 = warn("in w9", uplevel: 1); w9 }
t(10) { warn "x", uplevel: "1" }
t(11) { warn "x", uplevel: nil }
t(12) { warn 1, :sym, 2.5 }
t(13) { Warning.warn("no newline") ; puts }
t(14) { Warning.warn(:sym) }
t(15) { Warning.warn("x", category: :bogus) }
t(16) { module Warning; def self.warn(msg, category: nil, **kw) = print("W(#{category.inspect},#{kw}) #{msg}"); end; warn "via hook", category: :experimental; warn "d", category: :deprecated }
t(17) { Warning[:experimental] = true; warn "exp2", category: :experimental }
t(18) { $VERBOSE = nil; warn "silent?"; :after }
t(19) { $VERBOSE = false; warn "back" }
