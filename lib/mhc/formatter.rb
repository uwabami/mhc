# -*- coding: utf-8 -*-

module Mhc
  class FormatterNameError < StandardError; end

  class Formatter
    def self.build(formatter:, **options)
      case formatter.to_sym
      when :text
        Text.new(options)
      when :mail
        Mail.new(options)
      when :orgtable
        OrgTable.new(options)
      when :emacs
        # SymbolicExpression.new(options)
        Emacs.new(options)
      else
        raise FormatterNameError.new("Unknown format: #{formatter} (#{formatter.class})")
      end
    end

    class Base
      def initialize(options = nil)
        @items = {}
        @options = options
      end

      def <<(date_items)
        date, items = date_items
        @items[date] ||= []
        @items[date] += items
      end

      def to_s
        context = {:items => @items}.merge(@options)
        return format_header(context) + format_body(context) + format_footer(context)
      end

      ################################################################
      private

      def format_header(context)
        ""
      end

      def format_footer(context)
        ""
      end

      def format_body(context)
        context[:number] = 0
        @items.keys.sort.map{|date| format_day(context, date, @items[date]) }.join
      end

      def format_day(context, date, items)
        string = format_day_header(context, date)

        items.each_with_index do |schedule, count|
          context[:number] += 1
          context[:number_in_day] = count + 1
          string += format_item(context, date, schedule)
        end

        return string + format_day_footer(context, date)
      end

      def format_day_header(context, date)
        ""
      end

      def format_day_footer(context, date)
        ""
      end

      def format_item(context, date, item)
        format("%s%-11s %s%s\n",
               format_item_header(context, date, item),
               MhcKconv::todisp(item.time_as_string),
               MhcKconv::todisp(item.subject),
               MhcKconv::todisp(append(enclose(item.location))))
      end

      def format_item_header(context, date, item)
        if context[:number_in_day] == 1
          format("%02d/%02d %s ", date.m, date.d, date.w_s)
        else
          " " * 10
        end
      end

      ################################################################
      ## helpers
      def append(item, separator = " ")
        return "" if item.to_s.empty?
        return separator + item.to_s
      end

      def prepend(item, separator = " ")
        return "" if item.to_s.empty?
        return item.to_s + separator
      end

      def enclose(item, bracket = "[]")
        return "" if item.to_s.empty?
        return bracket[0] + item.to_s + bracket[1]
      end
    end

    class Text < Base
    end # class Text

    class Mail < Base
      private

      def format_header(context)
        mail_address = context[:mailto].to_s
        subject = format("MHC schedule report (%s--%s)", *context[:items].keys.minmax)
        header =  "To: #{mail_address}\n"
        header += "From: #{append(mail_address, "secretary-of-")}\n"
        header += "Subject: #{subject}\n"
        header += "Content-Type: Text/Plain; charset=utf-8\n"
        header += "Content-Transfer-Encoding: 8bit\n"
        header += "\n"
        header += format("* mhc %s--%s\n", *context[:items].keys.minmax)
      end
    end # class Mail

    class SymbolicExpression < Base
      private

      def format_header(context)
        "("
      end

      def format_footer(context)
        ")\n"
      end

      def format_day_header(context, date)
        format("((%2d %2d %4d) . (", date.m, date.d, date.y)
      end

      def format_item(context, date, item)
        '"' +
          format("%s%s%s",
                 MhcKconv::todisp(prepend(item.time_as_string)),
                 MhcKconv::todisp(item.subject),
                 MhcKconv::todisp(append(enclose(item.location)))).gsub(/[\"\\]/, '\\\\\&') +
          '" '
      end

      def format_day_footer(context, date)
        ")) "
      end
    end

    class Emacs < SymbolicExpression
      def format_day_header(context, date)
        format("(%d . [%d %d %d %d nil (", date.absolute_from_epoch, date.y, date.m, date.d, date.w)
      end

      def format_item(context, date, item)
        # [ RECORD CONDITION SUBJECT LOCATION (TIMEB . TIMEE) ALARM CATEGORIES PRIORITY REGION RECURRENCE-TAG]
        format("[(%s . [%s nil nil]) nil %s %s (%s . %s) %s (%s) nil nil %s]",
               elisp_string(item.path.to_s),
               elisp_string(item.rec_id.to_s),
               elisp_string(item.subject),
               elisp_string(item.location),
               (item.time_b ? (item.time_b.to_i / 60) : "nil"),
               (item.time_e ? (item.time_e.to_i / 60) : "nil"),
               elisp_string(item.alarm_as_string),
               item.category.map{|c| elisp_string(c.downcase)}.join(" "),
               elisp_string(item.recurrence_tag))
      end

      def format_day_footer(context, date)
        ")]) "
      end

      def elisp_string(string)
        '"' + MhcKconv::todisp(string).gsub(/[\"\\]/, '\\\\\&') + '"'
      end
    end



    class OrgTable < Base
      private

      def format_header(context)
        format("* mhc %s--%s\n", *context[:items].keys.minmax)
      end

      def format_item(context, date, item)
        # | No | Mission | Recurrence | Subject | Path | Date |
        format("  | %4d | %s | %s | %s | %s | [%04d-%02d-%02d%s] |\n",
               context[:number],
               MhcKconv::todisp(item.mission_tag),
               MhcKconv::todisp(item.recurrence_tag),
               MhcKconv::todisp(item.subject),
               item.path.to_s,
               date.y, date.m, date.d,
               append(item.time_as_string))
      end
    end # class OrgTable

  end # module Formatter
end # module Mhc