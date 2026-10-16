# frozen_string_literal: true

# The fixed shapes: ISO 8601, RFC 3339, XML Schema, RFC 2822, HTTP dates
# and JIS X 0301. Each returns the elements it finds, or nothing at all.

class Date
  ISO_EXT_DATETIME_RE = /\A\s*(?:([-+]?\d{2,}|-)-(\d{2})?(?:-(\d{2}))?|([-+]?\d{2,})?-(\d{3})|(\d{4}|\d{2})?-w(\d{2})-(\d)|-w-(\d))(?:t(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?(z|[-+]\d{2}(?::?\d{2})?)?)?\s*\z/i
  ISO_BAS_DATETIME_RE = /\A\s*(?:([-+]?(?:\d{4}|\d{2})|--)(\d{2}|-)(\d{2})|([-+]?(?:\d{4}|\d{2}))(\d{3})|-(\d{3})|(\d{4}|\d{2})w(\d{2})(\d)|-w(\d{2})(\d)|-w-(\d))(?:t?(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?)?(z|[-+]\d{2}(?:\d{2})?)?)?\s*\z/i
  ISO_EXT_TIME_RE = /\A\s*(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?(z|[-+]\d{2}(:?\d{2})?)?)?\s*\z/i
  ISO_BAS_TIME_RE = /\A\s*(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?(z|[-+]\d{2}(\d{2})?)?)?\s*\z/i
  RFC3339_RE = /\A\s*(-?\d{4})-(\d{2})-(\d{2})(t|\s)(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(z|[-+]\d{2}:\d{2})\s*\z/i
  XSD_DATETIME_RE = /\A\s*(-?\d{4,})(?:-(\d{2})(?:-(\d{2}))?)?(?:t(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?)?(z|[-+]\d{2}:\d{2})?\s*\z/i
  XSD_TIME_RE = /\A\s*(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(z|[-+]\d{2}:\d{2})?\s*\z/i
  XSD_TRUNC_RE = /\A\s*(?:--(\d{2})(?:-(\d{2}))?|---(\d{2}))(z|[-+]\d{2}:\d{2})?\s*\z/i
  RFC2822_RE = /\A\s*(?:(#{ABBR_DAYS})\s*,\s+)?(\d{1,2})\s+(#{ABBR_MONS})\s+(-?\d{2,})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([-+]\d{4}|ut|gmt|e[sd]t|c[sd]t|m[sd]t|p[sd]t|[a-ik-z])\s*\z/i
  HTTPDATE1_RE = /\A\s*(#{ABBR_DAYS})\s*,\s+(\d{2})\s+(#{ABBR_MONS})\s+(-?\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+(gmt)\s*\z/i
  HTTPDATE2_RE = /\A\s*(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s*,\s+(\d{2})\s*-\s*(#{ABBR_MONS})\s*-\s*(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+(gmt)\s*\z/i
  HTTPDATE3_RE = /\A\s*(#{ABBR_DAYS})\s+(#{ABBR_MONS})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})\s*\z/i
  JISX0301_RE = /\A\s*([mtshr])?(\d{2})\.(\d{2})\.(\d{2})(?:t(?:(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d*))?)?(z|[-+]\d{2}(?::?\d{2})?)?)?)?\s*\z/i
  private_constant :ISO_EXT_DATETIME_RE, :ISO_BAS_DATETIME_RE, :ISO_EXT_TIME_RE, :ISO_BAS_TIME_RE,
                   :RFC3339_RE, :XSD_DATETIME_RE, :XSD_TIME_RE, :XSD_TRUNC_RE, :RFC2822_RE,
                   :HTTPDATE1_RE, :HTTPDATE2_RE, :HTTPDATE3_RE, :JISX0301_RE

  class << self
    def _iso8601(text, **opts)
      text = limited(text, opts) unless text.nil?
      found = {}
      iso_ext_datetime(text, found) || iso_bas_datetime(text, found) ||
        iso_ext_time(text, found) || iso_bas_time(text, found)
      found
    end

    def _rfc3339(text, **opts)
      text = limited(text, opts) unless text.nil?
      found = {}
      m = RFC3339_RE.match(text) or return found

      # RFC 3339 has only "T" (and by custom a space) between the date
      # and the time (date 3.6.0).
      unless m[4] == "t" || m[4] == "T" || m[4] == " "
        Warning.send(:deprecated, "Invalid RFC3339 date time separator provided, this will raise an error in a future version.")
      end
      found.merge!(year: m[1].to_i, mon: m[2].to_i, mday: m[3].to_i,
                   hour: m[5].to_i, min: m[6].to_i, sec: m[7].to_i,
                   zone: m[9], offset: zone_to_diff(m[9]))
      found[:sec_fraction] = fraction_of(m[8]) if m[8]
      found
    end

    def _xmlschema(text, **opts)
      text = limited(text, opts) unless text.nil?
      found = {}
      xsd_datetime(text, found) || xsd_time(text, found) || xsd_trunc(text, found)
      found
    end

    def _rfc2822(text, **opts)
      text = limited(text, opts) unless text.nil?
      found = {}
      m = RFC2822_RE.match(text) or return found

      found[:wday] = day_num(m[1]) if m[1]
      year = m[4].to_i
      year = comp_year50(year) if m[4].length < 4
      found.merge!(mday: m[2].to_i, mon: mon_num(m[3]), year: year, hour: m[5].to_i, min: m[6].to_i)
      found[:sec] = m[7].to_i if m[7]
      found.merge!(zone: m[8], offset: zone_to_diff(m[8]))
    end

    alias _rfc822 _rfc2822

    def _httpdate(text, **opts)
      text = limited(text, opts) unless text.nil?
      found = {}
      httpdate1(text, found) || httpdate2(text, found) || httpdate3(text, found)
      found
    end

    def _jisx0301(text, **opts)
      text = limited(text, opts) unless text.nil?
      # date__jisx0301 falls back to the reader in C, past the check.
      return _iso8601(text, limit: nil) unless /\A\s*[mtshr]?\d{2}\.\d{2}\.\d{2}/i.match?(text)

      found = {}
      m = JISX0301_RE.match(text) or return found

      found.merge!(year: m[2].to_i + GENGO.fetch((m[1] || "h").downcase), mon: m[3].to_i, mday: m[4].to_i)
      if m[5]
        found[:hour] = m[5].to_i
        found[:min] = m[6].to_i if m[6]
        found[:sec] = m[7].to_i if m[7]
      end
      found[:sec_fraction] = fraction_of(m[8]) if m[8]
      found.merge!(zone: m[9], offset: zone_to_diff(m[9])) if m[9]
      found
    end

    private

    def fraction_of(digits)
      Primitive.attr! :hidden
      Rational(digits.to_i, 10**digits.length)
    end

    def comp_year50(year)
      Primitive.attr! :hidden
      year + (year >= 50 ? 1900 : 2000)
    end

    def comp_year69(year)
      Primitive.attr! :hidden
      year + (year >= 69 ? 1900 : 2000)
    end

    # A year of fewer than four digits is this century or the last.
    def wide_year(text)
      Primitive.attr! :hidden
      text.length < 4 ? comp_year69(text.to_i) : text.to_i
    end

    def iso_ext_datetime(text, found)
      Primitive.attr! :hidden
      m = ISO_EXT_DATETIME_RE.match(text) or return false

      if m[1]
        found[:mday] = m[3].to_i if m[3]
        found[:year] = wide_year(m[1]) unless m[1] == "-"
        if m[2].nil?
          return false unless m[1] == "-"
        else
          found[:mon] = m[2].to_i
        end
      elsif m[5]
        found[:yday] = m[5].to_i
        found[:year] = wide_year(m[4]) if m[4]
      elsif m[8]
        found.merge!(cweek: m[7].to_i, cwday: m[8].to_i)
        found[:cwyear] = wide_year(m[6]) if m[6]
      elsif m[9]
        found[:cwday] = m[9].to_i
      end
      iso_tail(found, m[10], m[11], m[12], m[13], m[14])
    end

    def iso_bas_datetime(text, found)
      Primitive.attr! :hidden
      m = ISO_BAS_DATETIME_RE.match(text) or return false

      if m[3]
        found[:mday] = m[3].to_i
        found[:year] = wide_year(m[1]) unless m[1] == "--"
        if m[2].start_with?("-")
          return false unless m[1] == "--"
        else
          found[:mon] = m[2].to_i
        end
      elsif m[5]
        found.merge!(yday: m[5].to_i, year: wide_year(m[4]))
      elsif m[6]
        found[:yday] = m[6].to_i
      elsif m[9]
        found.merge!(cweek: m[8].to_i, cwday: m[9].to_i, cwyear: wide_year(m[7]))
      elsif m[11]
        found.merge!(cweek: m[10].to_i, cwday: m[11].to_i)
      elsif m[12]
        found[:cwday] = m[12].to_i
      end
      iso_tail(found, m[13], m[14], m[15], m[16], m[17])
    end

    def iso_tail(found, hour, min, sec, fraction, zone)
      Primitive.attr! :hidden
      if hour
        found.merge!(hour: hour.to_i, min: min.to_i)
        found[:sec] = sec.to_i if sec
      end
      found[:sec_fraction] = fraction_of(fraction) if fraction
      found.merge!(zone: zone, offset: zone_to_diff(zone)) if zone
      true
    end

    def iso_ext_time(text, found)
      Primitive.attr! :hidden
      m = ISO_EXT_TIME_RE.match(text) or return false

      found.merge!(hour: m[1].to_i, min: m[2].to_i)
      found[:sec] = m[3].to_i if m[3]
      found[:sec_fraction] = fraction_of(m[4]) if m[4]
      found.merge!(zone: m[5], offset: zone_to_diff(m[5])) if m[5]
      true
    end

    def iso_bas_time(text, found)
      Primitive.attr! :hidden
      m = ISO_BAS_TIME_RE.match(text) or return false

      found.merge!(hour: m[1].to_i, min: m[2].to_i)
      found[:sec] = m[3].to_i if m[3]
      found[:sec_fraction] = fraction_of(m[4]) if m[4]
      found.merge!(zone: m[5], offset: zone_to_diff(m[5])) if m[5]
      true
    end

    def xsd_datetime(text, found)
      Primitive.attr! :hidden
      m = XSD_DATETIME_RE.match(text) or return false

      found[:year] = m[1].to_i
      found[:mon] = m[2].to_i if m[2]
      found[:mday] = m[3].to_i if m[3]
      found[:hour] = m[4].to_i if m[4]
      found[:min] = m[5].to_i if m[5]
      found[:sec] = m[6].to_i if m[6]
      found[:sec_fraction] = fraction_of(m[7]) if m[7]
      found.merge!(zone: m[8], offset: zone_to_diff(m[8])) if m[8]
      true
    end

    def xsd_time(text, found)
      Primitive.attr! :hidden
      m = XSD_TIME_RE.match(text) or return false

      found.merge!(hour: m[1].to_i, min: m[2].to_i)
      found[:sec] = m[3].to_i if m[3]
      found[:sec_fraction] = fraction_of(m[4]) if m[4]
      found.merge!(zone: m[5], offset: zone_to_diff(m[5])) if m[5]
      true
    end

    def xsd_trunc(text, found)
      Primitive.attr! :hidden
      m = XSD_TRUNC_RE.match(text) or return false

      found[:mon] = m[1].to_i if m[1]
      found[:mday] = m[2].to_i if m[2]
      found[:mday] = m[3].to_i if m[3]
      found.merge!(zone: m[4], offset: zone_to_diff(m[4])) if m[4]
      true
    end

    def httpdate1(text, found)
      Primitive.attr! :hidden
      m = HTTPDATE1_RE.match(text) or return false

      found.merge!(wday: day_num(m[1]), mday: m[2].to_i, mon: mon_num(m[3]), year: m[4].to_i,
                   hour: m[5].to_i, min: m[6].to_i, sec: m[7].to_i, zone: m[8], offset: 0)
      true
    end

    def httpdate2(text, found)
      Primitive.attr! :hidden
      m = HTTPDATE2_RE.match(text) or return false

      year = m[4].to_i
      year = comp_year69(year) if (0..99).cover?(year)
      found.merge!(wday: day_num(m[1]), mday: m[2].to_i, mon: mon_num(m[3]), year: year,
                   hour: m[5].to_i, min: m[6].to_i, sec: m[7].to_i, zone: m[8], offset: 0)
      true
    end

    def httpdate3(text, found)
      Primitive.attr! :hidden
      m = HTTPDATE3_RE.match(text) or return false

      found.merge!(wday: day_num(m[1]), mon: mon_num(m[2]), mday: m[3].to_i,
                   hour: m[4].to_i, min: m[5].to_i, sec: m[6].to_i, year: m[7].to_i)
      true
    end
  end
end
