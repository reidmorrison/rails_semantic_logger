require "ripper"

module RailsSemanticLogger
  module Generators
    # The Ruby source of the arguments of one method call, such as those of
    # `config.semantic_logger.add_appender(...)`, or the value of a setting.
    #
    # Knows whether they can move to the start of an environment's settings, into its appenders
    # block: only when they are the arguments of one call and nothing else, and read no local
    # variable of the file. It asks Ripper.
    class Arguments
      # Ruby's implicit block parameters, and the nodes that open a block of their own.
      IMPLICIT_PARAMETERS = (%w[it] + (1..9).map { |i| "_#{i}" }).freeze
      BLOCKS              = %i[brace_block do_block lambda].freeze

      def initialize(source)
        @source = source
      end

      # Whether the arguments can move into the appenders block.
      def movable?
        one_call? && !local_reference?
      end

      private

      def call = "f(#{@source})"

      # Whether `f(source)` is one call alone, not a call chained onto, assigned to, or followed by
      # another statement, as in `config.semantic_logger.add_appender(appender: :syslog).name = "syslog"`.
      def one_call?
        statements = Ripper.sexp(call)&.[](1)
        statements&.size == 1 && statements[0][0] == :method_add_arg
      end

      # Whether the arguments name a local variable, or call a method without a receiver, such as
      # `file_name: log_path` or `log_file("app")`, which the appenders block may not see, since it
      # moves to the start of the environment's settings. That includes `config`: the block runs before
      # the settings below it, so `level: config.log_level` would read the level before it is set.
      #
      # The parameters of a block or lambda in them, such as `log` in
      # `filter: ->(log) { log.level == :error }`, are not local variables of the file.
      def local_reference?
        # The arguments of `f(...)`, without the call to `f` that wraps them to parse them.
        references_local?(Ripper.sexp(call)&.dig(1, 0, 2), [])
      end

      # Whether the tree reads a local variable or calls a method without a receiver, other than the
      # parameters of the blocks it is inside of.
      def references_local?(node, parameters)
        return false unless node.is_a?(Array)

        if BLOCKS.include?(node[0])
          names, defaults = block_parameters(node[1])
          # `it` and `_1` are parameters only of a block that declares none of its own.
          inner = parameters + (names.empty? ? IMPLICIT_PARAMETERS : names)
          # A parameter's default value is read outside the block's own parameters.
          return defaults.any? { |default| references_local?(default, parameters) } ||
                 node[2..].any? { |child| references_local?(child, inner) }
        end

        return true if local_name?(node, parameters)

        node.any? { |child| references_local?(child, parameters) }
      end

      # Whether the node reads a local variable, or calls a method without a receiver, other than a
      # block parameter, or Ruby's own `lambda` and `proc`.
      def local_name?(node, parameters)
        ident = node[1] if node[1].is_a?(Array) && node[1][0] == :@ident
        return false unless ident && %i[vcall var_ref fcall command].include?(node[0])
        return false if %i[fcall command].include?(node[0]) && %w[lambda proc].include?(ident[1])

        !(%i[var_ref vcall].include?(node[0]) && parameters.include?(ident[1]))
      end

      # Returns [Array<String>, Array] the names of a block's or lambda's parameters, keyword ones and
      # block-local ones (`|x; y|`) included, and the trees of their default values.
      def block_parameters(node)
        block_locals = node.is_a?(Array) && node[0] == :block_var ? identifiers(node[2]) : []
        node = node[1] while node.is_a?(Array) && %i[paren block_var].include?(node[0])
        return [block_locals, []] unless node.is_a?(Array) && node[0] == :params

        _, required, optional, rest, post, keywords, keyword_rest, block = node
        names    = block_locals +
                   [required, post, rest, keyword_rest, block].flat_map { |slot| identifiers(slot) }
        defaults = []
        optional&.each do |name, default|
          names.concat(identifiers(name))
          defaults << default
        end
        keywords&.each do |label, default|
          names << label[1].delete_suffix(":")
          defaults << default if default
        end
        [names, defaults]
      end

      # The names of the identifiers in a parameter slot, such as those of `(a, b)`.
      def identifiers(node)
        return [] unless node.is_a?(Array)
        return [node[1]] if node[0] == :@ident

        node.flat_map { |child| identifiers(child) }
      end
    end
  end
end
