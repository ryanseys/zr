# Dir.glob raises when a directory does not open for a reason other
# than a missing name (here EMFILE), and warns under $VERBOSE for a
# directory that may not be read.
require "tmpdir"
require "stringio"
Dir.mktmpdir do |dir|
  Dir.mkdir("#{dir}/closed")
  File.chmod(0, "#{dir}/closed")
  $stderr = StringIO.new
  $VERBOSE = true
  p Dir.glob("#{dir}/closed/*")
  $VERBOSE = false
  warned = $stderr.string
  $stderr = STDERR
  p warned.include?("#{dir}/closed: Permission denied") unless Process.uid.zero?
  p Dir.glob("#{dir}/missing/*")
  File.chmod(0o755, "#{dir}/closed")
  pid = fork do
    Process.setrlimit(Process::RLIMIT_NOFILE, 16)
    files = []
    begin
      16.times { files << File.open(__FILE__) }
    rescue SystemCallError => e
      error = e.class
    end
    begin
      Dir.glob("#{dir}/*")
      puts "nothing raised"
    rescue error
      puts "raised #{error}"
    end
  end
  Process.wait(pid)
end
