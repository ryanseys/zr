# A File.join component of unknown type (here: an element read from a
# heterogeneous array) must join as its String value. doom's SoundManager
# builds its temp dir from a Dir.tmpdir value of unknown type.
parts = ["sounds", 7]
dir = parts[0]
path = File.join(dir, "doom_rb")
puts path
puts File.join("a", "b", "c")
