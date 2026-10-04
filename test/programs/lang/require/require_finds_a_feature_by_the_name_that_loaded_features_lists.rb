# A require compares its name with $LOADED_FEATURES before it searches,
# as ruby's rb_feature_p: an entry that is the name, or a $LOAD_PATH
# directory joined to it, is loaded. The bare name, or the name with the
# native extension, only limits the search to a `.rb` file, and no file
# is then not an error.
$rec = []
code = File.join(Dir.pwd, "code")
saved = $LOADED_FEATURES.clone
reset = -> { $LOADED_FEATURES.replace(saved); $rec = [] }
$LOADED_FEATURES << "./load_fixture.rb"
Dir.chdir(code) { p require("./load_fixture.rb"), $rec }
reset.()
$LOADED_FEATURES << "load_fixture"
$LOAD_PATH << code
p require("load_fixture"), $rec
reset.()
$LOADED_FEATURES << "no_such_feature"
p require("no_such_feature")
reset.()
$LOADED_FEATURES << File.join(code, "load_fixture.#{RbConfig::CONFIG["DLEXT"]}")
p require(File.join(code, "load_fixture")), $rec
reset.()
$LOAD_PATH.replace([code])
p require("load_fixture"), $rec
$LOAD_PATH.replace([File.join(code, "b"), code])
p require("load_fixture"), $rec
