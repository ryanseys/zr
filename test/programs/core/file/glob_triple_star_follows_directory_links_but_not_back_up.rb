# ruby 4.1's Dir.glob takes `***/` (Feature #17548): a recursive part
# that goes into links to directories, but not into a link back to a
# directory the walk came through, which only a trailing slash matches.
# Recursive parts in a row fold into one.
require "tmpdir"
Dir.mktmpdir("zrglob") do |d|
  Dir.chdir(d) do
    Dir.mkdir("a")
    Dir.mkdir("a/b")
    File.write("a/b/x.rb", "")
    File.write("a/y.rb", "")
    Dir.mkdir("other")
    File.write("other/z.rb", "")
    File.symlink("../other", "a/to_other")
    File.symlink("..", "a/b/up")
    File.symlink("b", "a/same")
    File.symlink("nowhere", "a/dangling")
    File.symlink("y.rb", "a/filelink.rb")
    Dir.mkdir("a/.hid")
    File.write("a/.hid/h.rb", "")
    File.symlink("../other", "a/.hidlink")
    %w[**/*.rb ***/*.rb a/***/*.rb ***/ a/**/ a/***/ **/***/*.rb ***/**/*.rb ***/***/z.rb *** ***.rb
       a/*** {a,other}/***/*.rb ***/up ***/up/ a/b/***/*.rb].each do |pat|
      puts "#{pat}: #{Dir.glob(pat).inspect}"
    end
    puts "dotmatch: #{Dir.glob("***/*.rb", File::FNM_DOTMATCH).inspect}"
    puts "base: #{Dir.glob("***/*.rb", base: "a").inspect}"
    puts "fnmatch: #{File.fnmatch("***/*.rb", "a/b/x.rb", File::FNM_PATHNAME)}"
  end
end
