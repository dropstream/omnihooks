require 'rack'
require 'singleton'
require 'logger'
require 'hashie'
require 'omnihooks/builder'
require 'omnihooks/strategy'

module OmniHooks

  module Strategies
  end

  # 
  # Collection of current strategies
  # 
  # @return [Array<Object>] strategy collection
  def self.strategies
    @strategies ||= []
  end

  class Configuration
    include Singleton

    attr_accessor :logger, :path_prefix, :allowed_request_methods

    def self.default_logger
      logger = Logger.new(STDOUT)
      logger.progname = 'omnihooks'
      logger
    end

    def self.defaults
      @defaults ||= {
        logger: default_logger,
        path_prefix: '/hooks',
        allowed_request_methods: [:post]
      }
    end

    def initialize
      self.class.defaults.each_pair { |k, v| send("#{k}=", v) }
    end
  end


  def self.config
    Configuration.instance
  end

  def self.configure
    yield config
  end

  def self.logger
    config.logger
  end

  module Utils
    module_function

    def deep_merge(hash, other_hash)
      target = hash.dup

      other_hash.keys.each do |key|
        if other_hash[key].is_a?(::Hash) && hash[key].is_a?(::Hash)
          target[key] = deep_merge(target[key], other_hash[key])
          next
        end

        target[key] = other_hash[key]
      end

      target
    end
  end
end
