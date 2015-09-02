require 'spec_helper'

RSpec.describe OmniHooks do
  describe '.strategies' do
    it 'increases when a new strategy is made' do
      expect {
        class ExampleStrategy
          include OmniHooks::Strategy
        end
      }.to change(OmniHooks.strategies, :size).by(1)
      expect(OmniHooks.strategies.last).to eq(ExampleStrategy)
    end
  end

  context 'configuration' do
    describe '.defaults' do
      it 'is a hash of default configuration' do
        expect(OmniHooks::Configuration.defaults).to be_kind_of(Hash)
      end
    end

    it 'is callable from .configure' do
      OmniHooks.configure do |c|
        expect(c).to be_kind_of(OmniHooks::Configuration)
      end
    end
  end

  describe '.logger' do
    it 'calls through to the configured logger' do
      allow(OmniHooks).to receive(:config).and_return(double(:logger => 'foo'))
      expect(OmniHooks.logger).to eq('foo')
    end
  end
end