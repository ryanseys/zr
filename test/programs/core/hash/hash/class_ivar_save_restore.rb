# A capture-style save/restore of a class-ivar that holds values of different
# types. @query_log gets nil, a bare `[]`, pushed strings, and the value restored
# from `prev`. The `prev = @query_log` local holds whichever of these the ivar
# has at that time.
class Db
  @query_log = nil
  def self.capture_sql
    prev = @query_log
    log = []
    @query_log = log
    begin
      yield
    ensure
      @query_log = prev
    end
    log
  end
  def self.record_query(sql)
    @query_log.push(sql) unless @query_log.nil?
  end
end

class ArticlesTest
  def test_index
    sql = Db.capture_sql { Db.record_query("SELECT 1"); Db.record_query("SELECT 2") }
    sql.length
  end
end
p ArticlesTest.new.test_index
