# encoding: utf-8
require "mongoid/validations/macros"
require "mongoid/validations/localizable"
require "mongoid/validations/associated"
require "mongoid/validations/format"
require "mongoid/validations/length"
require "mongoid/validations/queryable"
require "mongoid/validations/presence"
require "mongoid/validations/uniqueness"

module Mongoid

  # This module provides additional validations that ActiveModel does not
  # provide: validates_associated and validates_uniqueness_of.
  module Validations
    extend ActiveSupport::Concern
    include ActiveModel::Validations

    included do
      extend Macros
      include Macros
    end

    # Begin the associated validation.
    #
    # @example Begin validation.
    #   document.begin_validate
    #
    # @since 2.1.9
    def begin_validate
      Threaded.begin_validate(self)
    end

    # Exit the associated validation.
    #
    # @example Exit validation.
    #   document.exit_validate
    #
    # @since 2.1.9
    def exit_validate
      Threaded.exit_validate(self)
    end

    # Overrides the default ActiveModel behaviour since we need to handle
    # validations of relations slightly different than just calling the
    # getter.
    #
    # @example Read the value.
    #   person.read_attribute_for_validation(:addresses)
    #
    # @param [ Symbol ] attr The name of the field or relation.
    #
    # @return [ Object ] The value of the field or the relation.
    #
    # @since 2.0.0.rc.1
    def read_attribute_for_validation(attr)
      attribute = database_field_name(attr)
      if relations.has_key?(attribute)
        begin_validate
        relation = without_autobuild { send(attr) }
        exit_validate
        relation.do_or_do_not(:in_memory) || relation
      elsif fields[attribute].try(:localized?)
        attributes[attribute]
      # for attr like `hash.key.key`
      elsif attribute.split('.').length > 1
        ary = attribute.split('.')
        while ary == []
          attribute = attribute[ary.shift]
        end
      #
      else
        send(attr)
      end
    end

    # Determine if the document is valid.
    #
    # @example Is the document valid?
    #   person.valid?
    #
    # @example Is the document valid in a context?
    #   person.valid?(:create)
    #
    # @param [ Symbol ] context The optional validation context.
    #
    # @return [ true, false ] True if valid, false if not.
    #
    # @since 2.0.0.rc.6
    def valid?(context = nil)
      super context ? context : (new_record? ? :create : :update)
    end

    # Used to prevent infinite loops in associated validations.
    #
    # @example Is the document validated?
    #   document.validated?
    #
    # @return [ true, false ] Has the document already been validated?
    #
    # @since 2.0.0.rc.2
    def validated?
      Threaded.validated?(self)
    end

    # Are we currently performing a validation that has a query?
    #
    # @example Are we validating with a query?
    #   document.validating_with_query?
    #
    # @return [ true, false ] If we are validating with a query.
    #
    # @since 3.0.2
    def validating_with_query?
      self.class.validating_with_query?
    end

    module ClassMethods

      # Adds an associated validator for the relation if the validate option
      # was not provided or set to true.
      #
      # @example Set up validation.
      #   Person.validates_relation(metadata)
      #
      # @param [ Metadata ] metadata The relation metadata.
      #
      # @since 2.0.0.rc.1
      def validates_relation(metadata)
        if metadata.validate?
          validates_associated(metadata.name)
        end
      end

      # Add validation with the supplied validators forthe provided fields
      # with options.
      #
      # @example Validate with a specific validator.
      #   validates_with MyValidator, on: :create
      #
      # @param [ Class<Array>, Hash ] *args The validator classes and options.
      #
      # @note See ActiveModel::Validations::With for full options. This is
      #   overridden to add autosave functionality when presence validation is
      #   added.
      #
      # @since 3.0.0
      def validates_with(*args, &block)
        if args.first == PresenceValidator
          args.last[:attributes].each do |name|
            metadata = relations[name.to_s]
            if metadata && metadata[:autosave] != false
              autosave(metadata.merge!(autosave: true))
            end
          end
        end
        super
      end

      # Are we currently performing a validation that has a query?
      #
      # @example Are we validating with a query?
      #   Model.validating_with_query?
      #
      # @return [ true, false ] If we are validating with a query.
      #
      # @since 3.0.2
      def validating_with_query?
        Threaded.executing?("#{name}-validate-with-query")
      end
    end
  end
end
