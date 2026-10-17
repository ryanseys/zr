# ruby's boot loads enc/encdb and enc/trans/transdb, and lists them by
# their paths in the arch directory, after set.rb.
features = $LOADED_FEATURES.dup
db = features.index { |f| f.end_with?("/enc/trans/transdb.#{RbConfig::CONFIG["DLEXT"]}") }
p features[0..db].map { |f| File.basename(f) }
p features[db - 1, 2].map { |f| f.delete_prefix(RbConfig::CONFIG["archdir"]) }
p require("enc/encdb"), require("enc/trans/transdb")
