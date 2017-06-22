# OmniHooks: Standardized Multi-Provider Webhooks 

## Introduction

OmniHooks is a library that standardizes multi-provider webhooks for web applications. It was created to be powerful, flexible, and do as little as possible. Any developer can create strategies for OmniHooks that can handle webhooks via disparate systems.

In order to use OmniHooks in your applications, you will need to leverage one or more strategies. These strategies are generally released individually as RubyGems, and you can see a [community maintained list](https://github.com/dropstream/omnihooks/wiki/List-of-Strategies) on the wiki for this project.

## Getting Started

Each OmniHook strategy is a Rack Middleware. That means that you can use it the same way that you use any other Rack middleware. For example, to use the built-in Developer strategy in a Sinatra application I might do this:

````ruby
require 'sinatra'
require 'omnihooks'

class MyApplication < Sinatra::Base
  use Rack::Session::Cookie
  use OmniHooks::Strategies::Developer
end
````

Because OmniHooks is built for multi-provider webhooks, I may want to leave room to run multiple strategies. For this, the built-in OmniHooks::Builder class gives you an easy way to specify multiple strategies.

````ruby
require 'sinatra'
require 'omnihooks'

class MyApplication < Sinatra::Base
  use Rack::Session::Cookie
	use OmniHooks::Builder do
		provider :developer do |p|
			p.configure do |c|
				c.subscribe 'foo', Proc.new { |event| nil }
			end
		end
	  provider :core_warehouse do |p|
	  	p.configure do |c|
	  	  c.subscribe 'Shipment', Proc.new { |event| nil }
	  	end
	  end
	end
end
````

## Logging 

OmniHooks supports a configurable logger. By default, OmniHooks will log to STDOUT but you can configure this using `OmniHooks.config.logger`:

## Resources

The [OmniHooks Wiki](https://github.com/dropstream/omnihooks/wiki) has actively maintained in-depth documentation for OmniHooks. It should be your first stop if you are wondering about a more in-depth look at OmniHooks, how it works, and how to use it.
