require_relative "../install/logger_settings"

module RailsSemanticLogger
  module Generators
    # The settings of config/environments/development.rb or config/application.rb, as the
    # observability generator asks about them: whether they already send to OTLP or name the
    # application, and where the OTLP appenders can go.
    #
    # It adds these questions to LoggerSettings, which owns how a settings file is read: its top level,
    # its statements, and their conditions.
    class ObservabilitySettings < LoggerSettings
      # The start of an appenders block that more appenders can be added to.
      APPENDERS_DO = /
        ^(?<indent>[ \t]*)config\.rails_semantic_logger\.appenders\ do\ \|(?<name>\w+)\|[ \t]*(?:\#.*)?\r?\n
      /x

      # Returns [Array<Symbol>] what the file always sends to OTLP, of :logs (an OTLP log appender) and
      # :metrics (an OTLP metric appender): one that `config.semantic_logger.add_appender` adds, or `add`
      # in an appenders block (not `add_server` or `add_console`, which apply only sometimes), each at the
      # top level of the settings and of its block, with no condition of its own.
      def sends_to_otlp
        @lines.each_index.flat_map do |index|
          line = @lines[index]
          next [] if comment?(line) || !top_level?(index)

          if line.match?(ADD_APPENDER)
            statement = without_comments(@lines[index..statement_end(index)].join)
            conditional?(statement) ? [] : otlp_kinds(statement)
          elsif line.match?(APPENDERS)
            block_sends_to_otlp(index)
          else
            []
          end
        end.uniq
      end

      # Returns [Array<Symbol>] what the file sends to OTLP at all, of :logs and :metrics, including
      # through an appender that applies only sometimes, such as `add_server(metric: :otlp)` or one
      # with a condition. One that the file already has is not added again, which would send twice.
      def mentions_otlp
        otlp_kinds(without_comments(@lines.join))
      end

      # Returns [String|nil] the text with lines added at the end of its appenders block, and `after` after
      # the block, in the file's line endings, or nil when it has no `appenders do |name|` block at the
      # top level of its settings (one inside a condition applies only sometimes). Yields the block's
      # indentation and the name of its block variable, for the lines to add.
      def with_appenders_added(after: "")
        text  = @lines.join
        start = text.to_enum(:scan, APPENDERS_DO).map { Regexp.last_match }.find do |match|
          index = text[0...match.begin(0)].count("\n")
          top_level?(index) && !conditional?(without_comments(@lines[index..statement_end(index)].join))
        end
        return unless start

        indent = start[:indent]
        close  = text.match(/^#{Regexp.escape(indent)}end\b.*\r?\n/, start.end(0))
        return unless close

        eol = start[0].end_with?("\r\n") ? "\r\n" : "\n"
        lines = yield(indent, start[:name]).gsub(/\r?\n/, eol)
        text[0...close.begin(0)] + lines + close[0] + after.gsub(/\r?\n/, eol) + text[close.end(0)..]
      end

      # Whether the file declares appenders always: at the top level of its settings, without a
      # condition. Then more appenders declared in a block of their own add to them, rather than turn
      # off the default appenders where the condition does not hold.
      def always_declares_appenders?
        @lines.each_index.any? do |index|
          line = @lines[index]
          !comment?(line) && line.match?(APPENDERS) && top_level?(index) &&
            !conditional?(without_comments(@lines[index..statement_end(index)].join))
        end
      end

      # Whether the file always names the application: `config.semantic_logger.application = ...` at
      # the top level of its settings, with no condition.
      def names_application?
        @lines.each_index.any? do |index|
          @lines[index].match?(/\A\s*config\.semantic_logger\.application\s*=/) && top_level?(index) &&
            !conditional?(without_comments(@lines[index..statement_end(index)].join))
        end
      end

      private

      # What the appenders block that starts at the line always sends to OTLP (see #sends_to_otlp): its
      # `add` lines at the block's own top level, with no condition of their own. Nothing when the
      # block's statement has a condition.
      def block_sends_to_otlp(index)
        last = statement_end(index)
        return [] if conditional?(without_comments(@lines[index..last].join))
        return one_line_block_sends_to_otlp(without_comments(@lines[index])) if last == index

        name  = @lines[index][/\|\s*(\w+)\s*\|/, 1]
        inner = ((index + 1)...last).reject { |i| blank?(@lines[i]) || comment?(@lines[i]) }
        return [] unless name && inner.any?

        depth = indentation(@lines[inner.first])
        inner.flat_map do |i|
          next [] unless indentation(@lines[i]) == depth && @lines[i].match?(/\A\s*#{name}\.add\b(?!_)/)

          statement = without_comments(@lines[i..statement_end(i)].join)
          conditional?(statement) ? [] : otlp_kinds(statement)
        end
      end

      # `appenders { |a| a.add(...) }`, under the same rules as a block of several lines.
      def one_line_block_sends_to_otlp(source)
        block = source.match(/\{\s*\|\s*(?<name>\w+)\s*\|(?<body>.*)\}\s*\z/m)
        return [] unless block && block[:body].strip.match?(/\A#{block[:name]}\.add\b(?!_)/)
        return [] if conditional?(block[:body].strip)

        otlp_kinds(block[:body])
      end

      def otlp_kinds(source)
        logs    = source.match?(/\bappender:\s*:otlp\b|\bAppender::Otlp\b/)
        metrics = source.match?(/\bmetric:\s*:otlp\b|\bMetric::Otlp\b/)
        [(:logs if logs), (:metrics if metrics)].compact
      end
    end
  end
end
