require "active_support/inflector"

module OmniHooks
  class Builder < ::Rack::Builder

    def initialize(app = nil, &block)
      @options = nil
      if rack14?
        super
      else
        @app = app
        super(app, &block)
      end
    end

    def rack14?
      Rack.release.split('.')[0].to_i == 1 && Rack.release.split('.')[1].to_i >= 4
    end

    def on_failure(&block)
      OmniHooks.config.on_failure = block
    end

    def options(options = false)
      return @options || {} if options == false
      @options = options
    end

    def provider(klass, *args, &block)
      if klass.is_a?(Class)
        middleware = klass
      else
        begin
          middleware = OmniHooks::Strategies.const_get(klass.to_s.camelize)
        rescue NameError
          raise(LoadError.new("Could not find matching strategy for #{klass.inspect}. You may need to install an additional gem (such as omnihooks-#{klass})."))
        end
      end
      args.last.is_a?(Hash) ? args.push(options.merge(args.pop)) : args.push(options)
      use middleware, *args, &block
    end

    def call(env)
      to_app.call(env)
    end
  end
end