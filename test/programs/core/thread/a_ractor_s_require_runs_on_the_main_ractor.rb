# A ractor's require runs on the main ractor (rb_ractor_require): the
# file's classes and constants are the main ractor's, so the ractor reads
# only their shareable values, and the main ractor still changes them.
Warning[:experimental] = false
r = Ractor.new do
  require_relative "ractor_required"
  out = [RactorRequired.hello, RactorRequired::NAME]
  begin
    RactorRequired::LIST
  rescue Ractor::IsolationError => e
    out << e.message
  end
  begin
    RactorRequired.define_method(:x) { 1 }
  rescue Ractor::IsolationError => e
    out << e.message
  end
  out
end
r.value.each { |line| p line }
p RactorRequired::LIST
RactorRequired.define_method(:x) { 1 }
p RactorRequired.new.x
p $LOADED_FEATURES.count { |f| f.end_with?("ractor_required.rb") }
