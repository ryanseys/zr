# frozen_string_literal: true

# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# The elements that a reader found, made into a date: the largest set of
# elements that identifies a day wins, and missing elements come from today.

class Date
  FRAG_SETS = [
    [:time, %i[hour min sec]],
    [nil, %i[jd]],
    [:ordinal, %i[year yday hour min sec]],
    [:civil, %i[year mon mday hour min sec]],
    [:commercial, %i[cwyear cweek cwday hour min sec]],
    [:wday, %i[wday hour min sec]],
    [:wnum0, %i[year wnum0 wday hour min sec]],
    [:wnum1, %i[year wnum1 wday hour min sec]],
    [nil, %i[cwyear cweek wday hour min sec]],
    [nil, %i[year wnum0 cwday hour min sec]],
    [nil, %i[year wnum1 cwday hour min sec]]
  ].freeze
  private_constant :FRAG_SETS

  class << self
    def parse(text = "-4712-01-01", comp = true, start = ITALY, **opts) = frags_date(_parse(text, comp, **opts), start) || raise(Error, "invalid date")

    def iso8601(text = "-4712-01-01", start = ITALY, **opts) = frags_date(_iso8601(text, **opts), start) || raise(Error, "invalid date")

    def rfc3339(text = "-4712-01-01T00:00:00+00:00", start = ITALY, **opts) = frags_date(_rfc3339(text, **opts), start) || raise(Error, "invalid date")

    def xmlschema(text = "-4712-01-01", start = ITALY, **opts) = frags_date(_xmlschema(text, **opts), start) || raise(Error, "invalid date")

    def rfc2822(text = "Mon, 1 Jan -4712 00:00:00 +0000", start = ITALY, **opts) = frags_date(_rfc2822(text, **opts), start) || raise(Error, "invalid date")

    alias rfc822 rfc2822

    def httpdate(text = "Mon, 01 Jan -4712 00:00:00 GMT", start = ITALY, **opts) = frags_date(_httpdate(text, **opts), start) || raise(Error, "invalid date")

    def jisx0301(text = "-4712-01-01", start = ITALY, **opts) = frags_date(_jisx0301(text, **opts), start) || raise(Error, "invalid date")

    def strptime(text = "-4712-01-01", format = "%F", start = ITALY) = frags_date(_strptime(text, format), start) || raise(Error, "invalid date")

    private

    # The date the elements name, or nil, so every reader raises where
    # its own caller can see it.
    def frags_date(found, start)
      Primitive.attr! :hidden
      return nil if found.nil?

      start = valid_start(start)
      found = found.dup
      jd = frags_jd(found, start, false)
      jd && at(jd, 0, 0, 0, start, simple: true)
    end

    # The day the elements name. A plain civil date needs no completion.
    def frags_jd(found, start, datetime)
      Primitive.attr! :hidden
      if found[:jd].nil? && found[:yday].nil? && found[:year] && found[:mon] && found[:mday]
        jd = valid_civil_jd(found[:year], found[:mon], found[:mday], start)
        complete_time(found, 60) if datetime
        return jd
      end
      rewrite_frags(found)
      complete_frags(found, datetime)
      valid_date_frags(found, start)
    end

    # Seconds since the epoch represent a whole date and time.
    def rewrite_frags(found)
      Primitive.attr! :hidden
      seconds = found.delete(:seconds) or return

      seconds += found[:offset] if found[:offset]
      days, rest = seconds.divmod(86_400)
      hour, rest = rest.divmod(3600)
      min, rest = rest.divmod(60)
      sec, fraction = rest.divmod(1)
      found.merge!(jd: 2_440_588 + days, hour: hour, min: min, sec: sec, sec_fraction: fraction)
    end

    def complete_frags(found, datetime)
      Primitive.attr! :hidden
      kind, names, present = widest_frag_set(found)
      complete_kind(found, kind, names) if kind && names.length > present
      found[:jd] ||= Date.today.jd if kind == :time && datetime
      complete_time(found, 59)
    end

    def widest_frag_set(found)
      Primitive.attr! :hidden
      best = [nil, nil]
      present = 0
      FRAG_SETS.each do |kind, names|
        count = names.count { |name| !found[name].nil? }
        next unless count > present

        present = count
        best = [kind, names]
      end
      [*best, present]
    end

    # What a set is missing comes from today, up to its first element
    # that the reader did find.
    def complete_kind(found, kind, names)
      Primitive.attr! :hidden
      return found[:jd] = (Date.today - Date.today.wday + found[:wday]).jd if kind == :wday

      if kind == :ordinal
        found[:year] ||= Date.today.year
        found[:yday] ||= 1
        return
      end
      names.each do |name|
        break unless found[name].nil?

        found[name] = Date.today.send(name)
      end
      case kind
      when :civil then found[:mon] ||= 1; found[:mday] ||= 1
      when :commercial then found[:cweek] ||= 1; found[:cwday] ||= 1
      when :wnum0 then found[:wnum0] ||= 0; found[:wday] ||= 0
      when :wnum1 then found[:wnum1] ||= 0; found[:wday] ||= 1
      end
    end

    # A leap second reads as the last second of the minute. A DateTime of
    # a civil date takes only 60 as one, as dt_new_by_frags does.
    def complete_time(found, leap)
      Primitive.attr! :hidden
      found[:hour] ||= 0
      found[:min] ||= 0
      if found[:sec].nil?
        found[:sec] = 0
      elsif leap == 60 ? found[:sec] == 60 : found[:sec] > 59
        found[:sec] = 59
      end
    end

    # The first shape the elements make a real day in.
    def valid_date_frags(found, start)
      Primitive.attr! :hidden
      return found[:jd] if found[:jd]

      if found[:yday] && found[:year] && (jd = valid_ordinal_jd(found[:year], found[:yday], start))
        return jd
      end
      if found[:mday] && found[:mon] && found[:year] &&
         (jd = valid_civil_jd(found[:year], found[:mon], found[:mday], start))
        return jd
      end
      commercial_frags(found, start) || weeknum_frags(found, start, 0) || weeknum_frags(found, start, 1)
    end

    def commercial_frags(found, start)
      Primitive.attr! :hidden
      wday = found[:cwday]
      if wday.nil? && found[:wday]
        wday = found[:wday].zero? ? 7 : found[:wday]
      end
      return nil unless wday && found[:cweek] && found[:cwyear]

      valid_commercial_jd(found[:cwyear], found[:cweek], wday, start)
    end

    def weeknum_frags(found, start, first)
      Primitive.attr! :hidden
      week = found[first.zero? ? :wnum0 : :wnum1]
      wday = found[:wday]
      if first.zero?
        wday = (found[:cwday] == 7 ? 0 : found[:cwday]) if wday.nil?
      else
        wday ||= found[:cwday]
        wday = (wday - 1) % 7 if wday
      end
      return nil unless wday && week && found[:year]

      valid_weeknum_jd(found[:year], week, wday, first, start)
    end

    # A week number counted from the first `first` day of the year.
    def weeknum_jd(year, week, wday, first, start)
      Primitive.attr! :hidden
      base = first_day_jd(year, start) + 6
      (base - (((base - first) + 1) % 7) - 7) + (7 * week) + wday
    end

    def jd_weeknum(jd, first, start)
      Primitive.attr! :hidden
      year = jd_civil(jd, start).first
      base = first_day_jd(year, start) + 6
      j = jd - (base - (((base - first) + 1) % 7)) + 7
      [year, j / 7, j % 7]
    end

    def valid_weeknum_jd(year, week, wday, first, start)
      Primitive.attr! :hidden
      wday += 7 if wday.negative?
      jd = weeknum_jd(year, week, wday, first, start)
      jd_weeknum(jd, first, start) == [year, week, wday] ? jd : nil
    end
  end
end

class DateTime < Date
  class << self
    def parse(text = "-4712-01-01T00:00:00+00:00", comp = true, start = Date::ITALY, **opts) = frags_date(_parse(text, comp, **opts), start) || raise(Date::Error, "invalid date")

    def iso8601(text = "-4712-01-01T00:00:00+00:00", start = Date::ITALY, **opts) = frags_date(_iso8601(text, **opts), start) || raise(Date::Error, "invalid date")

    def rfc3339(text = "-4712-01-01T00:00:00+00:00", start = Date::ITALY, **opts) = frags_date(_rfc3339(text, **opts), start) || raise(Date::Error, "invalid date")

    def xmlschema(text = "-4712-01-01T00:00:00+00:00", start = Date::ITALY, **opts) = frags_date(_xmlschema(text, **opts), start) || raise(Date::Error, "invalid date")

    def rfc2822(text = "Mon, 1 Jan -4712 00:00:00 +0000", start = Date::ITALY, **opts) = frags_date(_rfc2822(text, **opts), start) || raise(Date::Error, "invalid date")

    alias rfc822 rfc2822

    def httpdate(text = "Mon, 01 Jan -4712 00:00:00 GMT", start = Date::ITALY, **opts) = frags_date(_httpdate(text, **opts), start) || raise(Date::Error, "invalid date")

    def jisx0301(text = "-4712-01-01T00:00:00+00:00", start = Date::ITALY, **opts) = frags_date(_jisx0301(text, **opts), start) || raise(Date::Error, "invalid date")

    # datetime_s__strptime: Date's reader, with a time and a zone in the
    # format that it takes by default.
    def _strptime(text, format = "%FT%T%z") = super

    def strptime(text = "-4712-01-01T00:00:00+00:00", format = "%FT%T%z", start = Date::ITALY)
      frags_date(_strptime(text, format), start) || raise(Date::Error, "invalid date")
    end

    private

    def frags_date(found, start)
      Primitive.attr! :hidden
      return nil if found.nil?

      start = valid_start(start)
      found = found.dup
      jd = frags_jd(found, start, true) or return nil

      df, = time_of_day(found[:hour], found[:min], found[:sec], 0)
      of = offset_seconds(found[:offset])
      total = (((jd * 86_400) + df - of) * 1_000_000_000) + (Rational(found[:sec_fraction] || 0) * 1_000_000_000)
      jd, rest = total.divmod(86_400 * 1_000_000_000)
      df, sf = rest.divmod(1_000_000_000)
      at(jd, df.to_i, sf.denominator == 1 ? sf.to_i : sf, of, start)
    end

    # An offset past a whole day is no offset at all.
    def offset_seconds(offset)
      Primitive.attr! :hidden
      return 0 if offset.nil?

      seconds = offset.to_i
      return seconds if seconds.abs <= 86_400

      warn("invalid offset is ignored", uplevel: 0) if $VERBOSE
      0
    end
  end
end
