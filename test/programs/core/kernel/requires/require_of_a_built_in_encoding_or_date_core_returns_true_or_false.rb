p require("enc/euc_jp")
p require("enc/euc_jp")
p require("enc/trans/japanese")
p require("enc/encdb")
p require("enc/trans/transdb")
p $LOADED_FEATURES.count { |f| f.end_with?("/enc/euc_jp.#{RbConfig::CONFIG["DLEXT"]}") }
name = "enc/utf_16le"
p require(name)
p require(name)
begin
  require "ractor"
  puts "ractor loaded"
rescue LoadError => e
  puts e.message
end
p require("date_core")
p Date.civil(2026, 10, 3).to_s
p defined?(Date::VERSION)
p require("date")
p Date::VERSION.match?(/\A\d+\.\d+\.\d+/)
p Date::Infinity.new > Date.today.jd
p require("date_core")
