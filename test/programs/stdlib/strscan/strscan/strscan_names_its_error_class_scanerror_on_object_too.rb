require "strscan"
# strscan also names its error class on Object.
p ScanError, ScanError.equal?(StringScanner::Error)
p (StringScanner.new("a").unscan rescue $!).class
