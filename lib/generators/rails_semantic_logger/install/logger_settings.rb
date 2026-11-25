require "ripper"

module RailsSemanticLogger
  module Generators
    # The logger settings in one Rails configuration file, such as config/environments/production.rb.
    #
    # Knows which of them Rails Semantic Logger ignores or refuses, and removes them:
    # - `config.logger = ...`, which Rails Semantic Logger replaces, including the multi-line form
    #   of Rails 7.2 (`ActiveSupport::Logger.new(STDOUT).tap { ... }.then { ... }`);
    # - `config.log_formatter = ...`, which it never reads;
    # - the `if ENV["RAILS_LOG_TO_STDOUT"].present?` block of Rails 6 and 7.0, when it does nothing else;
    # - commented-out examples of another Rails logger, such as Syslog::Logger, and the comments
    #   directly above each removed setting;
    # - the deprecated appender options (Options::DEPRECATED_APPENDER_OPTIONS), keeping the value each
    #   was set to;
    # - and, when asked to, `config.semantic_logger.add_appender(...)`, keeping its arguments, since an
    #   application that lists its appenders lists those too.
    #
    # It keeps `config.log_level` and `config.log_tags`, which Rails Semantic Logger reads. It removes
    # only the settings of the file's top level: one inside a condition, or with a condition of its
    # own, applies only sometimes, so it is left in place for the application to move, and reported.
    # It works on the text line by line, and asks Ripper where each statement ends.
    class LoggerSettings
      # text:      [String] the text without the settings it removed.
      # removed:   [Array<String>] each line it removed.
      # options:   [Hash] the value of each deprecated appender option, by name, as Ruby source.
      # appenders: [Array<String>] the arguments of each `config.semantic_logger.add_appender` it removed.
      # left:      [Array<String>] each setting it left in place, for the application to move.
      Result = Struct.new(:text, :removed, :options, :appenders, :left, keyword_init: true)

      IGNORED = /\A\s*config\.(?:logger|log_formatter)\s*(?:\|\|)?=/
      DEPRECATED_OPTION =
        /\A\s*config\.rails_semantic_logger\.(#{Options::DEPRECATED_APPENDER_OPTIONS.join('|')})\s*=\s*(.*)\z/m
      ADD_APPENDER     = /\A\s*config\.semantic_logger\.add_appender\b/
      APPENDER_ARGS    = /\A\s*config\.semantic_logger\.add_appender\s*(?:\((?<args>.*)\)|\s(?<args>.*))\z/m
      LOG_TO_STDOUT    = /\A(\s*)(?:if|unless)\b.*RAILS_LOG_TO_STDOUT/
      COMMENTED_LOGGER = %r{\A\s*#\s*(?:config\.logger\s*=|require\s+["']syslog/logger["'])}
      COMMENTED_CODE   = /\A\s*#\s*config\./
      APPENDERS        = /config\.rails_semantic_logger\.appenders\b/
      COLORIZE_OFF     = /\A\s*config\.colorize_logging\s*=\s*false\b/
      # The start of an environment's settings, `Rails.application.configure do` or
      # `MyApp::Application.configure do`, with the comment that Rails writes first, if any.
      CONFIGURE = /
        ^[ \t]*(?:Rails\.application|[\w:]+::Application)\.configure\ do(?:[ \t]*\|\w+\|)?[ \t]*(?:\#.*)?\r?\n
        (?<comment>[ \t]*\#\ Settings\ specified\ here\ will\ take\ precedence.*\r?\n)?
      /x
      # A line that loads the settings of another environment, such as `require_relative "production"`.
      LOADS_FILE = %r{\A\s*require(?:_relative)?\b.*["'](?:\./)?(?<name>\w+)(?:\.rb)?["']}
      # The start of the settings of config/application.rb.
      APPLICATION_CLASS = /\A\s*class\s+\S+\s*<\s*(?:::)?Rails::Application\b/
      SCREEN           = /\bio:\s*(?:\$stdout|\$stderr|STDOUT|STDERR)\b/
      OPENS_BLOCK      = /(?:\bdo(?:\s*\|[^|]*\|)?|\A\s*(?:class|module)\b.*)\s*\z/
      CLOSES_BLOCK     = /\A\s*end\b/

      # What the RAILS_LOG_TO_STDOUT block of Rails 6 and 7.0 holds. A block that holds anything else,
      # such as `config.rails_semantic_logger.add_file_appender = false`, is left in place.
      LOG_TO_STDOUT_LINE = /
        \A\s*(?:\#|end\b|config\.(?:logger|log_formatter)\s*=|logger(?:\.formatter)?\s*=|(?:\$stdout|STDOUT)\.sync\s*=)
      /x

      # The comment that Rails 8 writes above `config.log_tags` and `config.logger`, which no longer
      # holds once `config.logger` is gone, and what it becomes.
      RAILS_COMMENTS = {
        "# Log to STDOUT with the current request id as a default log tag." =>
          "# Tag every log entry with the current request id."
      }.freeze

      def initialize(text)
        @lines = text.lines
      end

      # Whether the file declares appenders through `config.rails_semantic_logger.appenders`.
      def declares_appenders?
        @lines.any? { |line| !comment?(line) && line.match?(APPENDERS) }
      end

      # Whether the arguments of an appender write to the screen: stdout or stderr.
      def self.screen_appender?(args)
        args.match?(SCREEN)
      end

      # Whether the file adds an appender that writes to the screen with
      # `config.semantic_logger.add_appender`.
      # Only an unconditional one at the top level counts: one with a condition writes to the screen
      # only sometimes.
      def adds_screen_appender?
        @lines.each_index.any? do |index|
          next false unless @lines[index].match?(ADD_APPENDER) && top_level?(index)

          statement = without_comments(@lines[index..statement_end(index)].join)
          !conditional?(statement) && self.class.screen_appender?(statement)
        end
      end

      # Returns [String|nil] the text with the block added at the start of the environment's
      # settings, after the comment that Rails writes there first and the blank line after it, in the
      # file's line endings, or nil when the file has no `.configure do` block.
      def with_block(block)
        text  = @lines.join
        start = text.match(CONFIGURE)
        return unless start

        position = start.end(0)
        if start[:comment]
          blank = text[position..][/\A[ \t]*\r?\n/]
          blank ? position += blank.size : block = "\n#{block}"
        end
        block = block.gsub(/\r?\n/, "\r\n") if start[0].end_with?("\r\n")
        text.insert(position, block)
      end

      # Whether the file loads the settings of one of the environments, such as a staging.rb that
      # starts with `require_relative "production"`, and so gets that environment's appenders too.
      def loads_environment?(environments)
        @lines.any? do |line|
          name = line.match(LOADS_FILE)&.[](:name)
          !comment?(line) && name && environments.include?(name)
        end
      end

      # Whether the file turns colorized logging off, which makes the default log file plain text.
      def colorize_logging_off?
        @lines.any? { |line| line.match?(COLORIZE_OFF) }
      end

      # Returns [Result] the text without the settings that Rails Semantic Logger ignores or refuses.
      #
      # convert_appenders: [true|false] whether to remove each `config.semantic_logger.add_appender`,
      # keeping its arguments for the appenders that the application will list.
      def clean(convert_appenders: false)
        @removed = Array.new(@lines.size, false)
        @result  = Result.new(removed: [], options: {}, appenders: [], left: [])
        @convert = convert_appenders
        index    = 0
        index    = visit(index) + 1 while index < @lines.size
        remove_comments_above_removed

        kept            = kept_lines
        kept            = reword_rails_comments(kept) if @removed.any?
        @result.text    = tidy_blank_lines(kept).join
        @result.removed = @lines.select.with_index { |_, i| @removed[i] }
        @result
      end

      private

      # Handles the setting that starts at the line, if any, and returns the index of its last line.
      def visit(index)
        line = @lines[index]
        if (match = line.match(LOG_TO_STDOUT))
          log_to_stdout(index, match[1])
        elsif line.match?(IGNORED) || line.match?(DEPRECATED_OPTION) || (@convert && line.match?(ADD_APPENDER))
          setting(index)
        else
          remove(index, index) if line.match?(COMMENTED_LOGGER)
          index
        end
      end

      def log_to_stdout(index, indent)
        last = ((index + 1)...@lines.size).find { |i| @lines[i].match?(/\A#{indent}end\b/) }
        return index unless last

        only_logger = @lines[(index + 1)..last].all? { |line| blank?(line) || line.match?(LOG_TO_STDOUT_LINE) }
        top_level?(index) && only_logger ? remove(index, last) : leave(index, last)
      end

      def setting(index)
        last      = statement_end(index)
        statement = without_comments(@lines[index..last].join)
        return leave(index, last) if !top_level?(index) || conditional?(statement)

        if (option = statement.match(DEPRECATED_OPTION))
          @result.options[option[1].to_sym] = option[2].strip
        elsif statement.match?(ADD_APPENDER)
          args = statement.match(APPENDER_ARGS)&.[](:args)
          return leave(index, last) unless args && Ripper.sexp("f(#{args})") && !local_reference?(args)

          @result.appenders << args.strip
        end
        remove(index, last)
      end

      def remove(first, last)
        (first..last).each { |i| @removed[i] = true }
        last
      end

      def leave(first, last)
        @result.left << @lines[first..last].join.strip
        last
      end

      # The last line of the statement that starts at the line: the first one at which the lines so far
      # parse as Ruby, unless the next line continues it with a method call (`.tap`).
      def statement_end(index)
        (index...@lines.size).each do |last|
          next unless Ripper.sexp(@lines[index..last].join)
          return last unless @lines[last + 1]&.lstrip&.start_with?(".")
        end
        index
      end

      # Whether the arguments name a local variable, or call a method without a receiver, such as
      # `file_name: log_path` or `log_file("app")`, which the appenders block may not see, since it
      # moves to the start of the environment's settings. That includes `config`: the block runs before
      # the settings below it, so `level: config.log_level` would read the level before it is set.
      def local_reference?(args)
        locals = lambda do |node|
          next false unless node.is_a?(Array)

          ident = node[1] if node[1].is_a?(Array) && node[1][0] == :@ident
          # `lambda { ... }` and `proc { ... }` are Ruby's own; what they read is checked below.
          kernel = %i[fcall command].include?(node[0]) && %w[lambda proc].include?(ident&.[](1))
          next true if ident && %i[vcall var_ref fcall command].include?(node[0]) && !kernel

          node.any?(&locals)
        end
        # The arguments of `f(...)`, without the call to `f` that wraps them to parse them.
        locals.call(Ripper.sexp("f(#{args})")&.dig(1, 0, 2))
      end

      # Whether the statement has a condition of its own, such as `... if ENV["JSON"]`.
      def conditional?(statement)
        %i[if_mod unless_mod].include?(Ripper.sexp(statement)&.dig(1, 0, 0))
      end

      # Whether the line is at the top level of the file's settings: as indented as the first line of
      # code inside its `.configure do` block, or its `class Application < Rails::Application`.
      def top_level?(index)
        indentation(@lines[index]) <= top_indentation
      end

      def top_indentation
        @top_indentation ||= begin
          opener = @lines.index { |line| line.match?(CONFIGURE) || line.match?(APPLICATION_CLASS) }
          first  = opener && @lines[(opener + 1)..].find { |line| !blank?(line) && !comment?(line) }
          first ? indentation(first) : (@lines.grep(/\A\s*config\./).map { |line| indentation(line) }.min || 0)
        end
      end

      def indentation(line) = line[/\A[ \t]*/].size

      # The source of a statement, without its comments.
      def without_comments(source)
        Ripper.lex(source).reject { |token| token[1] == :on_comment }.map { |token| token[2] }.join.strip
      end

      # Removes the comment lines directly above each removed setting, such as "# Log to STDOUT by
      # default" above Rails 7.2's `config.logger`, stopping at a blank line, at code, and at
      # commented-out code, such as `# config.cache_store = :mem_cache_store`.
      def remove_comments_above_removed
        @lines.each_index do |i|
          next unless @removed[i] && (i.zero? || !@removed[i - 1])

          above = i - 1
          while above >= 0 && comment?(@lines[above]) && !@lines[above].match?(COMMENTED_CODE)
            @removed[above] = true
            above -= 1
          end
        end
      end

      # The lines it keeps, with a :gap where each run of removed lines was.
      def kept_lines
        @lines.each_with_index.with_object([]) do |(line, i), kept|
          if @removed[i]
            kept << :gap unless kept.last == :gap
          else
            kept << line
          end
        end
      end

      def reword_rails_comments(lines)
        lines.map do |line|
          reworded = line.is_a?(String) && RAILS_COMMENTS[line.strip]
          reworded ? line.sub(line.strip, reworded) : line
        end
      end

      # Drops a blank line that a removal left beside another blank line, the start of the file, or the
      # start or end of a block, such as where the lines that followed
      # `class Application < Rails::Application` were. Only the blank lines beside a gap: the rest of
      # the file, its heredocs included, is unchanged.
      def tidy_blank_lines(lines)
        lines.each_with_index.with_object([]) do |(line, i), kept|
          next if line == :gap
          next if blank?(line) && i.positive? && lines[i - 1] == :gap && after_gap_redundant?(kept.last)
          next if blank?(line) && lines[i + 1] == :gap && before_gap_redundant?(lines[i + 2])

          kept << line
        end
      end

      # Whether a blank line that follows a gap is redundant, given the line kept before the gap.
      def after_gap_redundant?(previous)
        previous.nil? || blank?(previous) || previous.match?(OPENS_BLOCK)
      end

      # Whether a blank line that precedes a gap is redundant, given the line after the gap.
      def before_gap_redundant?(following)
        following.nil? || (following.is_a?(String) && (blank?(following) || following.match?(CLOSES_BLOCK)))
      end

      def blank?(line) = line.strip.empty?

      def comment?(line) = line.lstrip.start_with?("#")
    end
  end
end
