# ruby 4.1's ENV.fetch_values (Feature #21781): each name's value as a
# fetch of one argument gives it. ENV.to_a is ENV's own method.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}#{" #{e.key.inspect} #{e.receiver.equal?(ENV)}" if e.is_a?(KeyError)}"
end
ENV["ZR_FV_A"] = "1"
ENV["ZR_FV_B"] = "two"
ENV.delete("ZR_FV_NONE")
t("both") { ENV.fetch_values("ZR_FV_A", "ZR_FV_B") }
t("none") { ENV.fetch_values }
t("missing") { ENV.fetch_values("ZR_FV_A", "ZR_FV_NONE") }
t("block") { ENV.fetch_values("ZR_FV_A", "ZR_FV_NONE") { |k| k.downcase } }
t("symbol") { ENV.fetch_values(:ZR_FV_A) }
t("int") { ENV.fetch_values(1) }
o = Object.new
def o.to_str = "ZR_FV_B"
t("to_str") { ENV.fetch_values(o) }
t("frozen") { ENV.fetch_values("ZR_FV_A").first.frozen? }
t("arity") { ENV.method(:fetch_values).arity }
t("to_a") { ENV.to_a.assoc("ZR_FV_B") }
t("to_a frozen") { ENV.to_a.assoc("ZR_FV_B").map(&:frozen?) }
t("to_a arity") { ENV.method(:to_a).arity }
t("to_a arg") { ENV.to_a(1) }
t("to_a size") { ENV.to_a.size == ENV.size }
