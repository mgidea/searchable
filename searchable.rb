module Searchable
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def search_filter(search = '')
      #search is coming from params, so it should be handled as a string
      if search.respond_to?(:to_s)
        search = search.to_s
      else
        return
      end
      # yield the scope if search term is valid.  Define validation in define_search_filter within class
      unless (defined_search_filter? ? self.send(:defined_search_filter, search) : default_search_filter(search))
        yield
      end
    end

    def defined_search_filter?
      self.respond_to?(:defined_search_filter)
    end

    def define_search_filter(search, &block)
      #add a different filter for the class
      self.define_singleton_method(:defined_search_filter, search, &block)
    end

    def default_search_filter(search = '')
      search.nil? || search.strip.empty?
    end

    def simple_search(search, query)
      if query.is_a?(Hash)
        search_filter(search) {where(query)}
      else
        search_filter(search) {where(query + sanitize("%#{search.strip}%"))}
      end
    end

    def search_or_chain(search, *args)
      args = args.unshift(search) if with_methods?(args)
      search_filter(search) {or_chain(*args)}
    end

    def with_methods?(args = [])
      args.last.is_a?(Symbol) || args.last.is_a?(String)
    end

    def or_chain(*args)
      # check if it is a list of methods or a list of variables
      create_chain(chain_args(args))
    end

    def chain_args(args = [])
      if with_methods?(args)
        search, args = remove_first(args)
        args = args.map{|arg| self.send(arg, search)}
      end
      arel_args(args)
    end

    def arel_args(args = [])
      Array.wrap(args).map(&:prep_or)
    end

    def create_chain(arelized_args = [], method = :or)
      chain, arelized_args = remove_first(arelized_args)
      arelized_args.each do |arg|
        chain = chain.send(method, arg)
      end
      where(chain)
    end

    def remove_first(args)
      [args.first, args[1..-1]]
    end
  end
end

class ActiveRecord::Relation
  def active_or(or_arg)
    arel_self = self.prep_or
    if or_arg.is_a?(ActiveRecord::Relation)
      arel_self.or(or_arg.prep_or)
    elsif or_arg.is_a?(Arel::Nodes::Node)
      arel_self.or(or_arg)
    else
      raise "argument must be an ActiveRecord::Relation or Arel::Nodes::Node"
    end
  end
  def method_missing(meth, *args, &block)
    if meth == :or && args.size == 1
      active_or(args.first)
    else
      super(meth, *args, &block)
    end
  end

  def prep_or
    constraints.first
  end
end

module Arel
  module Nodes
    class Node
      def or(right)
        if right.is_a?(ActiveRecord::Relation)
          active_or(right)
        else
          Nodes::Grouping.new Nodes::Or.new(self, right)
        end
      end

      def active_or(right)
        if right.is_a?(ActiveRecord::Relation)
          self.or(right.constraints.first)
        else
          self.or(right)
        end
      end
    end
  end
end
