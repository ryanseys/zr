# The P-B core classes: File, Dir, Time, Process, ENV.
#
# Everything here is zone- and machine-independent on purpose: Time uses a
# fixed epoch read in UTC, paths are built under a scratch directory this
# script creates, and nothing prints a real pid/clock/environment value --
# only facts about them. That is what lets the output be diffed against real
# ruby at all.

# --- Dir and File, on a real scratch tree ----------------------------------
# (`Dir.mktmpdir`/`Dir.tmpdir` are stdlib's tmpdir.rb, not core -- built by
# hand here so the example needs no require. The pid keeps concurrent runs
# from colliding.)
root = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_core_classes_#{Process.pid}")
Dir.mkdir(root)
begin
  Dir.chdir(root) do
    Dir.mkdir("sub")
    File.write("one.rb", "alpha\nbeta\n")
    File.write("two.txt", "")
    File.write("sub/three.rb", "gamma\n")

    p File.read("one.rb")
    p File.readlines("one.rb")
    p File.readlines("one.rb", chomp: true)
    p File.size("one.rb")
    p File.exist?("one.rb"), File.exist?("nope.rb")
    p File.file?("one.rb"), File.file?("sub")
    p File.directory?("sub"), File.directory?("one.rb")
    p File.zero?("two.txt"), File.zero?("one.rb")
    p File.size?("two.txt")   # nil for an EMPTY file, not 0
    p File.size?("one.rb")

    # Dir listing and globbing.
    p Dir.children(".").sort
    p Dir.entries(".").sort
    p Dir.glob("*.rb").sort
    p Dir.glob("**/*.rb").sort
    p Dir.glob("*.{rb,txt}").sort
    p Dir.glob("?ne.rb")
    p Dir["*.rb"]
    p Dir.exist?("sub"), Dir.exist?("nope")
    p Dir.empty?("sub")

    # File.open: the block form closes afterwards and answers the block's
    # value; a lengthed read at EOF is nil where a whole-rest read is "".
    File.open("counted.txt", "w") { |f| f.print "ABCDEFGHIJ" }
    File.open("counted.txt", "r") do |f|
      p f.read(5)
      p f.read(5)
      p f.read(5)      # nil at EOF
      f.rewind
      p f.read(2)
      p f.tell
      f.seek(0)
      p f.read
      p f.eof?
    end
    p File.open("counted.txt", "r") { |f| f.read(3) }

    # A closed file raises rather than reading garbage.
    h = File.open("counted.txt", "r")
    h.close
    p h.closed?
    begin
      h.read
    rescue IOError => e
      puts "IOError: #{e.message}"
    end

    File.delete("two.txt")
    p File.exist?("two.txt")
    File.rename("one.rb", "renamed.rb")
    p File.exist?("renamed.rb")

    # Clean the tree from the inside, so the ensure below only has to remove
    # the (now empty) root.
    Dir.glob("**/*").sort.reverse.each do |e|
      File.directory?(e) ? Dir.rmdir(e) : File.delete(e)
    end
  end
ensure
  Dir.rmdir(root) if Dir.exist?(root)
end

