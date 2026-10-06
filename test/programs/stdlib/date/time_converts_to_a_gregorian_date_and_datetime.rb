require "date"
t = Time.new(2024, 1, 2, 3, 4, 5.25r, "+05:30")
p t.to_date, t.to_date.start
p t.to_datetime, t.to_datetime.offset
p Time.utc(1500, 3, 1).to_date, Time.utc(1500, 3, 1).to_datetime
p t.to_time.equal?(t)
