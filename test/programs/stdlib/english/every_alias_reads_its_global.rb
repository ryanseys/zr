require "English"
p $DEFAULT_INPUT.class, $DEFAULT_INPUT.equal?($<), $DEFAULT_OUTPUT.equal?($>)
"hello world" =~ /o (w)/
p $MATCH, $PREMATCH, $POSTMATCH, $LAST_PAREN_MATCH, $LAST_MATCH_INFO
begin
  raise "x"
rescue
  p $ERROR_INFO, $ERROR_POSITION.class
end
$_ = "line"
p $LAST_READ_LINE
p $PID == $$, $PROCESS_ID == $$, $PROGRAM_NAME == $0, $ARGV.equal?($*), $FIELD_SEPARATOR, $INPUT_RECORD_SEPARATOR, $OUTPUT_FIELD_SEPARATOR
p $FS, $RS, $ORS, $OFS, $NR == $., $INPUT_LINE_NUMBER
system("true"); p $CHILD_STATUS.class
p $IGNORECASE rescue p $!
