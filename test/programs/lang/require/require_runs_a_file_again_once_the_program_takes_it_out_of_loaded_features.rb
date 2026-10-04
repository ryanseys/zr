# A require runs a file again once the program takes its path out of
# $LOADED_FEATURES, by any spelling of the path, as ruby does.
$rec = []
dir = File.join(Dir.pwd, "code")
saved = $LOADED_FEATURES.clone
path = File.expand_path("load_fixture.rb", dir)
p require(path), $rec
$LOADED_FEATURES.replace(saved)
$rec = []
p require(path), $rec
$LOADED_FEATURES.replace(saved)
$rec = []
p require(File.join(dir, "..", "code", "load_fixture.rb")), $rec
$LOADED_FEATURES.replace(saved)
$rec = []
p load(path), $rec
p require(path), $rec
p require(path), $rec
