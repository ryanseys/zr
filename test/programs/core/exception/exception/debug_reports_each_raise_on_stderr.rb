$DEBUG = true
def m = raise(IOError, "io")
begin; m; rescue IOError; end
begin; raise RuntimeError, "set", ["elsewhere:9"]; rescue; end
begin; [].fetch(3); rescue IndexError; end
begin; throw :zz; rescue UncaughtThrowError; end
begin; exit 3; rescue SystemExit; end
catch(:a) { throw :a }
$DEBUG = false
begin; raise "quiet"; rescue; end
puts "done"
