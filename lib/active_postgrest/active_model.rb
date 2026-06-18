# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

require 'active_model'
require 'active_postgrest'

module ActivePostgrest
  module ActiveModelSupport
    def self.included(base)
      base.include ::ActiveModel::Validations
      base.extend  ::ActiveModel::Naming
      base.include ::ActiveModel::Conversion
      base.prepend SaveWithValidations
    end

    def read_attribute_for_validation(key)
      @attributes[key.to_s]
    end

    # Returns primary key value(s) for ActionView form helpers.
    def to_key
      pk = self.class.primary_key
      val = @attributes[pk]
      val ? [val] : nil
    end

    module SaveWithValidations
      def save
        return false unless valid?

        super
      end
    end
  end
end

ActivePostgrest::Base.include(ActivePostgrest::ActiveModelSupport)
