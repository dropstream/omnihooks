module OmniHooks
  module Strategies
    # The Developer strategy is a very simple strategy that can be used as a
    # placeholder in your application until a different authentication strategy
    # is swapped in. It has zero security and should *never* be used in a
    # production setting.
    #
    # ## Usage
    #
    # To use the Developer strategy, all you need to do is put it in like any
    # other strategy:
    #
    # @example Basic Usage
    #
    #   use OmniAuth::Builder do
    #     provider :developer
    #   end
    #
    # @example Custom Fields
    #
    #   use OmniAuth::Builder do
    #     provider :developer,
    #       :fields => [:first_name, :last_name],
    #       :uid_field => :last_name
    #   end
    #
    # This will create a strategy that, when the user visits `/auth/developer`
    # they will be presented a form that prompts for (by default) their name
    # and email address. The auth hash will be populated with these fields and
    # the `uid` will simply be set to the provided email.
    class Developer
      include OmniHooks::Strategy

      event_type do
        params[:type]
      end

      event do
        params
      end
    end
  end
end