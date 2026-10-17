# CSV.open and CSV.foreach of a StringIO read with "bom|utf-8" when the
# default external encoding is UTF-8, so the first field has no BOM.
require "csv"
require "stringio"

data = "﻿name\tage\r\nann\t3\r\n"
p CSV.foreach(StringIO.new(data), col_sep: "\t", row_sep: "\r\n").to_a
p CSV.foreach(StringIO.new(data), col_sep: "\t", row_sep: "\r\n", headers: true).map(&:to_h)
p CSV.foreach(StringIO.new(data), "r:utf-8", col_sep: "\t", row_sep: "\r\n").first
p CSV.foreach(StringIO.new(data), encoding: "utf-8", col_sep: "\t", row_sep: "\r\n").first
p CSV.parse(data, col_sep: "\t", row_sep: "\r\n").first
