require_relative "../metacrunch"

module Metacrunch::Hash
  def self.add(object, *args)
    if args.length < 2
      raise ArgumentError
    else
      return args.last if args.last.nil? || (args.last.respond_to?(:empty?) && args.last.empty?)

      if args.length == 2
        args_first_is_a_string = args.first.is_a?(String) # memoize

        if args_first_is_a_string && args.first.include?("/")
          add(object, *args.first.split("/"), args.last)
        else
          if args_first_is_a_string && args.first.start_with?(":")
            _add(object, args.first[1..-1].to_sym, args.last)
          else
            _add(object, args.first, args.last)
          end
        end
      else
        nested_hash = args[0..-3].inject(object) do |_memo, _key|
          if _key.is_a?(String) && _key.start_with?(":")
            _key = _key[1..-1].to_sym
          end

          _memo[_key] ||= object.class.new
        end

        _add(nested_hash, args[-2], args[-1])
      end
    end
  end

  private

  def self._add(hash, key, value)
    #if value.is_a?(FalseClass) || (value.respond_to?(:empty?) ? !value.empty? : !!value) # like ActiveSupport implements blank?/present?
    if hash[key].nil?
      hash[key] = value.is_a?(Array) && value.length == 1 ? value.first : value
    elsif hash[key].is_a?(Array)
      (hash[key] << value).flatten!(1)
    else
      (hash[key] = [hash[key], value]).flatten!(1)
    end
    #end

    hash[key]
  end
end
