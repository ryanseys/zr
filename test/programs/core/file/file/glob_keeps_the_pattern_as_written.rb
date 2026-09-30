# A glob answers the pattern as it is written: a leading `./` stays on
# every match, and so does a literal segment in the middle of it. A
# pattern with no magic answers itself where the file is there.
require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    File.write("thing.rb", "")
    Dir.mkdir("sub")
    File.write("sub/deep.rb", "")
    p Dir.glob("./*").sort
    p Dir["./*.rb"]
    p Dir.glob("./**/*.rb").sort
    p Dir.glob(".")
    p Dir.glob("./")
    p Dir.glob("*").sort
    p Dir.glob("./sub/../*").sort
    p Dir.glob("sub/*")
    p Dir.glob("./nope*")
    p Dir.glob("./sub/")
  end
end

