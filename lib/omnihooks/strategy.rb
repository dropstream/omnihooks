require "active_support/notifications"

module OmniHooks
  # The Strategy is the base unit of OmniHooks's ability to
  # wrangle multiple providers. Each strategy provided by
  # OmniHooks includes this mixin to gain the default functionality
  # necessary to be compatible with the OmniHooks library.
  module Strategy # rubocop:disable ModuleLength
    def self.included(base)
      OmniHooks.strategies << base

      base.extend ClassMethods
      base.class_eval do
        option :backend, ActiveSupport::Notifications
        option :adapter, OmniHooks::Strategy::NotificationAdapter
        option :namespace_delimiter, '.'
      end
    end

    module ClassMethods
      attr_accessor :namespace
      # Returns an inherited set of default options set at the class-level
      # for each strategy.
      def default_options
        return @default_options if instance_variable_defined?(:@default_options) && @default_options
        existing = superclass.respond_to?(:default_options) ? superclass.default_options : {}
        @default_options = OmniHooks::Strategy::Options.new(existing)
      end

      # Directly declare a default option for your class. This is a useful from
      # a documentation perspective as it provides a simple line-by-line analysis
      # of the kinds of options your strategy provides by default.
      #
      # @param name [Symbol] The key of the default option in your configuration hash.
      # @param value [Object] The value your object defaults to. Nil if not provided.
      #
      # @example
      #
      #   class MyStrategy
      #     include OmniAuth::Strategy
      #
      #     option :foo, 'bar'
      #     option
      #   end
      def option(name, value = nil)
        default_options[name] = value
      end

      # Sets (and retrieves) option key names for initializer arguments to be
      # recorded as. This takes care of 90% of the use cases for overriding
      # the initializer in OmniAuth Strategies.
      def args(args = nil)
        if args
          @args = Array(args)
          return
        end
        existing = superclass.respond_to?(:args) ? superclass.args : []
        (instance_variable_defined?(:@args) && @args) || existing
      end
      # This allows for more declarative subclassing of strategies by allowing
      # default options to be set using a simple configure call.
      #
      # @param options [Hash] If supplied, these will be the default options (deep-merged into the superclass's default options).
      # @yield [Options] The options Mash that allows you to set your defaults as you'd like.
      #
      # @example Using a yield to configure the default options.
      #
      #   class MyStrategy
      #     include OmniHooks::Strategy
      #
      #     configure_options do |c|
      #       c.foo = 'bar'
      #     end
      #   end
      #
      # @example Using a hash to configure the default options.
      #
      #   class MyStrategy
      #     include OmniHooks::Strategy
      #     configure_options foo: 'bar'
      #   end
      def configure_options(options = nil)
        if block_given?
          yield default_options
        else
          default_options.deep_merge!(options)
        end
      end

      def configure(&block)
        raise ArgumentError, "must provide a block" unless block_given?
        block.arity.zero? ? instance_eval(&block) : yield(self)
      end
      alias :setup :configure

      def subscribe(name, callable = Proc.new)
        backend.subscribe(namespace.to_regexp(name), adapter.call(callable))
      end

      def all(callable = Proc.new)
        backend.subscribe(nil, callable)
      end

      def listening?(name)
        namespaced_name = namespace.call(name)
        backend.notifier.listening?(namespaced_name)
      end
      #protected
      %w(event_type event).each do |fetcher|
        class_eval <<-RUBY
          def #{fetcher}(&block)
            @#{fetcher}_proc = nil unless defined?(@#{fetcher}_proc)

            return @#{fetcher}_proc unless block_given?
            @#{fetcher}_proc = block
          end
          def #{fetcher}_stack(context)
            compile_stack(self.ancestors, :#{fetcher}, context)
          end
        RUBY
      end

      def instrument(event_type, event_object)
        backend.instrument(namespace.call(event_type), event_object)
      end

      private

      def compile_stack(ancestors, method, context)
        stack = ancestors.inject([]) do |a, ancestor|
          a << context.instance_eval(&ancestor.send(method)) if ancestor.respond_to?(method) && ancestor.send(method)
          a
        end
        stack.reverse!
      end

      def adapter
        default_options.adapter
      end

      def backend
        default_options.backend
      end

      def namespace
        @namespace ||= OmniHooks::Strategy::Namespace.new(default_options.name, default_options.namespace_delimiter)
      end
    end

    class Namespace < Struct.new(:prefix, :delimiter)
      def call(name = nil)
        "#{prefix}#{delimiter}#{name}"
      end

      def to_regexp(name = nil)
        %r{^#{Regexp.escape(call(name))}}
      end
    end

    class NotificationAdapter < Struct.new(:subscriber)
      def self.call(callable)
        new(callable)
      end

      def call(*args)
        payload = args.last
        subscriber.call(payload)
      end
    end

    class Options < Hashie::Mash; end

    attr_reader :options

    # Initializes the strategy by passing in the Rack endpoint,
    # the unique URL segment name for this strategy, and any
    # additional arguments. An `options` hash is automatically
    # created from the last argument if it is a hash.
    #
    # @param app [Rack application] The application on which this middleware is applied.
    #
    # @overload new(app, options = {})
    #   If nothing but a hash is supplied, initialized with the supplied options
    #   overriding the strategy's default options via a deep merge.
    # @overload new(app, *args, options = {})
    #   If the strategy has supplied custom arguments that it accepts, they may
    #   will be passed through and set to the appropriate values.
    #
    # @yield [Class, Options] Yields Parent class and options to block for further configuration.
    def initialize(app, *args, &block) # rubocop:disable UnusedMethodArgument
      @app = app
      @env = nil
      @options = self.class.default_options.dup

      options.deep_merge!(args.pop) if args.last.is_a?(Hash)

      self.class.args.each do |arg|
        break if args.empty?
        options[arg] = args.shift
      end

      # Make sure that all of the args have been dealt with, otherwise error out.
      fail(ArgumentError.new("Received wrong number of arguments. #{args.inspect}")) unless args.empty?

      yield self.class, options if block_given?
    end

    def inspect
      "#<#{self.class}>"
    end

    # Duplicates this instance and runs #call! on it.
    # @param [Hash] The Rack environment.
    def call(env)
      dup.call!(env)
    end
    # The logic for dispatching any additional actions that need
    # to be taken. For instance, calling the request phase if
    # the request path is recognized.
    #
    # @param env [Hash] The Rack environment.
    def call!(env) # rubocop:disable CyclomaticComplexity, PerceivedComplexity
      @env = env

      return instrument if on_request_path? && OmniHooks.config.allowed_request_methods.include?(request.request_method.downcase.to_sym)

      @app.call(env)
    end

    def request
      @request ||= Rack::Request.new(@env)
    end

    protected
    attr_reader :app, :env

    # Direct access to the OmniAuth logger, automatically prefixed
    # with this strategy's name.
    #
    # @example
    #   log :warn, "This is a warning."
    def log(level, message)
      OmniHooks.logger.send(level, "(#{name}) #{message}")
    end

    private

    CURRENT_PATH_REGEX = %r{/$}
    EMPTY_STRING       = ''.freeze

    def instrument
      # instance needs to lookup and from the paylook the event type
      begin
        evt = get_event
        evt_type = get_event_type
        self.class.instrument(evt_type, evt) if evt
      rescue => e
        log(:error, e.message)
        [500, {}, [nil]]
      else
        # Send a 200 response back to
        [200, {}, [nil]]
      end
    end

    def path_prefix
      options[:path_prefix] || OmniHooks.config.path_prefix
    end

    def name
      options.name
    end

    def request_path
      @request_path ||= options[:request_path].is_a?(String) ? options[:request_path] : "#{path_prefix}/#{name}"
    end

    def on_request_path?
      if options.request_path.respond_to?(:call)
        options.request_path.call(env)
      else
        on_path?(request_path)
      end
    end

    def on_path?(path)
      current_path.casecmp(path) == 0
    end

    def current_path
      @current_path ||= request.path_info.downcase.sub(CURRENT_PATH_REGEX, EMPTY_STRING)
    end

    def get_event_type
      self.class.event_type_stack(self).last
    end

    def get_event
      self.class.event_stack(self).last
    end

  end
end