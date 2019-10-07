# frozen_string_literal: true

module ExceptionHandling
  module HoneybadgerCallbacks
    class << self
      def register_callbacks
        if ExceptionHandling.honeybadger_defined?
          Honeybadger.local_variable_filter(&method(:local_variable_filter))
        end
      end

      private

      def inspect_object(object, filter_keys)
        inspection_output = object.inspect

        if contains_filter_key?(filter_keys, inspection_output)
          filtered_object(object)
        else
          inspection_output
        end
      rescue => ex
        details = if object.respond_to?(:to_pk)
                    " @pk=#{object.to_pk}"
                  elsif object.respond_to?(:id)
                    " @id=#{object.id}"
                  end

        "#<#{object.class.name}#{details} [error '#{ex.class.name}: #{ex.message}' while calling #inspect]>"
      end

      def local_variable_filter(_symbol, object, filter_keys)
        case object
        # Honeybadger will filter these data types for us
        when String, Hash, Array, Set, Numeric, TrueClass, FalseClass, NilClass
          object
        else # handle other Ruby objects, intended for POROs
          inspect_object(object, filter_keys)
        end
      end

      def contains_filter_key?(filter_keys, string)
        filter_keys._?.any? { |key| string.include?(key) }
      end

      def filtered_object(object)
        # make the output look similar to inspect
        # use [FILTERED], just like honeybadger does
        if object.respond_to?(:to_pk)
          "#<#{object.class.name} @pk=#{object.to_pk}, [FILTERED]>"
        elsif object.respond_to?(:id)
          "#<#{object.class.name} @id=#{object.id}, [FILTERED]>"
        else
          "#<#{object.class.name} [FILTERED]>"
        end
      end
    end
  end
end
