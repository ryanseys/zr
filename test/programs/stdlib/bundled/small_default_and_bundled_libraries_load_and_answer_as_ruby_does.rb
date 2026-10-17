# Small default and bundled libraries that no other test requires load
# and answer as ruby does, and a URI that names no file raises as in
# ruby.
def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

require "find"
t(:find) { Dir.mkdir("fz") rescue nil; File.write("fz/a", ""); Find.find("fz").to_a.sort }
require "getoptlong"
t(:getoptlong) { ARGV.replace(%w[--a 1 x]); g = GetoptLong.new(["--a", GetoptLong::REQUIRED_ARGUMENT]); r = []; g.each { |k, v| r << [k, v] }; [r, ARGV] }
require "matrix"
t(:matrix) { m = Matrix[[1, 2], [3, 4]]; [m.det, m.inverse, m * m, m.transpose, Vector[1, 2].inner_product(Vector[3, 4])] }
t(:observer) { require "observer"; c = Class.new { include Observable }; o = c.new; r = []; w = Object.new; w.define_singleton_method(:update) { |x| r << x }; o.add_observer(w); o.changed; o.notify_observers(5); r }
t(:mutex_m) { require "mutex_m"; o = Object.new.extend(Mutex_m); o.synchronize { 1 } }
t(:power_assert) { require "power_assert"; PowerAssert.respond_to?(:start) }
t(:un) { require "un"; respond_to?(:cp, true) }
t(:open_uri) { require "open-uri"; URI.open("nope-file-zz") }
