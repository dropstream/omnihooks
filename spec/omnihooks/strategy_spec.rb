require 'spec_helper'

def make_env(path = '/hooks/test', props = {})
  {
    'REQUEST_METHOD' => 'POST',
    'PATH_INFO' => path,
    'rack.session' => {},
    'rack.input' => StringIO.new('test=true'),
  }.merge(props)
end


RSpec.describe OmniHooks::Strategy do
  let(:app) do
    lambda { |_env| [404, {}, ['Awesome']] }
  end

  let(:fresh_strategy) do
    c = Class.new
    c.send(:include, OmniHooks::Strategy)
  end

  describe '.default_options' do
    it 'is inherited from a parent class' do
      superklass = Class.new
      superklass.send :include, OmniHooks::Strategy
      superklass.configure_options do |c|
        c.foo = 'bar'
      end

      klass = Class.new(superklass)
      expect(klass.default_options.foo).to eq('bar')
    end
  end

  describe '.configure_options' do
    subject do
      c = Class.new
      c.send(:include, OmniHooks::Strategy)
    end

    context 'when block is passed' do
      it 'allows for default options setting' do
        subject.configure_options do |c|
          c.wakka = 'doo'
        end
        expect(subject.new(nil).options['wakka']).to eq('doo')
      end

      it "works when block doesn't evaluate to true" do
        environment_variable = nil
        subject.configure_options do |c|
          c.abc = '123'
          c.hgi = environment_variable
        end
        expect(subject.new(nil).options['abc']).to eq('123')
      end
    end

    it 'takes a hash and deep merge it' do
      subject.configure_options :abc => {:def => 123}
      subject.configure_options :abc => {:hgi => 456}
      expect(subject.new(nil).options['abc']).to eq('def' => 123, 'hgi' => 456)
    end
  end

  describe '.option' do
    subject do
      c = Class.new
      c.send(:include, OmniHooks::Strategy)
    end
    it 'sets a default value' do
      subject.option :abc, 123
      expect(subject.new(nil).options.abc).to eq(123)
    end

    it 'sets the default value to nil if none is provided' do
      subject.option :abc
      expect(subject.new(nil).options.abc).to be_nil
    end
  end

  describe '.args' do
    subject do
      c = Class.new
      c.send(:include, OmniHooks::Strategy)
    end

    it 'sets args to the specified argument if there is one' do
      subject.args [:abc, :def]
      expect(subject.args).to eq([:abc, :def])
    end

    it 'is inheritable' do
      subject.args [:abc, :def]
      c = Class.new(subject)
      expect(c.args).to eq([:abc, :def])
    end

    it 'accepts corresponding options as default arg values' do
      subject.args [:a, :b]
      subject.option :a, '1'
      subject.option :b, '2'

      expect(subject.new(nil).options.a).to eq '1'
      expect(subject.new(nil).options.b).to eq '2'
      expect(subject.new(nil, '3', '4').options.b).to eq '4'
      expect(subject.new(nil, nil, '4').options.a).to eq nil
    end
  end

  describe '.instrument' do
    subject do
      c = Class.new
      c.send(:include, OmniHooks::Strategy)
      c.option :name, 'class'
      c
    end

    it 'should forward event publication to backend' do
      expect(ActiveSupport::Notifications).to receive(:instrument).with('class.foo', 'bar')
      subject.instrument('foo', 'bar')
    end

  end

  context 'fetcher procs' do
    subject { fresh_strategy }
    %w(event event_type).each do |fetcher|
      describe ".#{fetcher}" do
        it 'sets and retrieve a proc' do
          proc = lambda { 'Hello' }
          subject.send(fetcher, &proc)
          expect(subject.send(fetcher)).to eq(proc)
        end
      end
    end
  end

  context 'fetcher stacks' do
    subject { fresh_strategy }
    %w(event event_type).each do |fetcher|
      describe ".#{fetcher}_stack" do
        it 'is an array of called ancestral procs' do
          fetchy = proc { 'Hello' }
          subject.send(fetcher, &fetchy)
          expect(subject.send("#{fetcher}_stack", subject.new(app))).to eq(['Hello'])
        end
      end
    end
  end

  describe '#initialize' do
    context 'options extraction' do
      it 'is the last argument if the last argument is a Hash' do
        expect(ExampleStrategy.new(app, :abc => 123).options[:abc]).to eq(123)
      end

      it 'is the default options if any are provided' do
        allow(ExampleStrategy).to receive(:default_options).and_return(OmniHooks::Strategy::Options.new(:abc => 123))
        expect(ExampleStrategy.new(app).options.abc).to eq(123)
      end
    end

    context 'custom args' do
      subject do
        c = Class.new
        c.send(:include, OmniHooks::Strategy)
      end

      it 'sets options based on the arguments if they are supplied' do
        subject.args [:abc, :def]
        s = subject.new app, 123, 456
        expect(s.options[:abc]).to eq(123)
        expect(s.options[:def]).to eq(456)
      end
    end
  end

  describe '#call' do
    before(:all) do
      @options = nil
    end

    let(:strategy) { ExampleStrategy.new(app, @options || {}) }

    it 'duplicates and calls' do
      klass = Class.new
      klass.send :include, OmniHooks::Strategy
      instance = klass.new(app)
      expect(instance).to receive(:dup).and_return(instance)
      instance.call('rack.session' => {})
    end

    context 'without a subscriber' do
      it 'should return a sucess response' do
        klass = Class.new
        klass.send :include, OmniHooks::Strategy
        klass.option :name, 'class'
        klass.event { 'Foo' }
        klass.event_type { 'bar' }
        instance = klass.new(app)

        expect(ActiveSupport::Notifications).to receive(:instrument).with('class.bar', 'Foo')

        expect(instance.call(make_env('/hooks/class'))).to eq([200, {}, [nil]])
      end

      context 'with exception in event callback' do
        let(:klass) { Class.new }
        before(:each) do
          
          klass.send :include, OmniHooks::Strategy
          klass.option :name, 'class'
          klass.event { raise 'Foo' }
        end

        it 'should not raise an error' do
          instance = klass.new(app)
          expect { instance.call(make_env('/hooks/class')) }.not_to raise_error
        end
        
        it 'should return a non 200 response' do
          instance = klass.new(app)
          expect(instance.call(make_env('/hooks/class'))).to eq([500, {}, [nil]])
        end
      end
    end

    context 'with an explicit subscriber' do
      let(:subscriber) { Proc.new { nil } }
      before(:each) do

        ExampleStrategy.event { 'Foo' }
        ExampleStrategy.event_type { request.params['type'] }
        ExampleStrategy.configure do |events|
          events.subscribe('foo.bar', subscriber)
        end
      end

      context 'with matched event type' do
        it 'should return a success response' do
          expect(subscriber).to receive(:call).with('Foo')

          expect(strategy.call(make_env('/hooks/test', {'rack.input' => StringIO.new('type=foo.bar&payload=test')}))).to eq([200, {}, [nil]])
        end
      end

      context 'with unmatched event' do
        it 'should return a success response' do
          expect(subscriber).not_to receive(:call)

          expect(strategy.call(make_env('/hooks/test', {'rack.input' => StringIO.new('type=foo.sam&payload=test')}))).to eq([200, {}, [nil]])
        end
      end

      context 'with an exception in the subscriber' do
        before(:each) do
          expect(subscriber).to receive(:call).and_raise(RuntimeError)
        end

        it 'should return an error response' do
          expect(strategy.call(make_env('/hooks/test', {'rack.input' => StringIO.new('type=foo.bar&payload=test')}))).to eq([500, {}, [nil]])
        end
      end

      after(:each) do
        # reset the handlers
        ExampleStrategy.event
        ExampleStrategy.event_type
      end
    end

    context 'request method restriction' do
      before do
        OmniHooks.config.allowed_request_methods = [:put]
      end

      it 'does not allow a request method of the wrong type' do
        expect { strategy.call(make_env) }.not_to raise_error
      end

      it 'forwards request method of the wrong type to application' do
        expect(strategy.call(make_env)).to eq([404, {}, ['Awesome']])
      end

      it 'allows a request method of the correct type' do
        expect(strategy.call(make_env('/hooks/test', 'REQUEST_METHOD' => 'PUT'))).to eq([200, {}, [nil]])
      end

      after do
        OmniHooks.config.allowed_request_methods = [:post]
      end
    end
  end

  describe '#inspect' do
    it 'returns the class name' do
      expect(ExampleStrategy.new(app).inspect).to eq('#<ExampleStrategy>')
    end
  end
end