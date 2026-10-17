# YAML::Store, PStore's YAML form, writes a transaction's values as YAML.
require "yaml/store"
s = YAML::Store.new("ys.yml")
s.transaction { s[:a] = [1] }
puts File.read("ys.yml")
p s.transaction(true) { s[:a] }
