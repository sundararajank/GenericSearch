class ActiveRecord::Base

  def _generic_search(args)
    if args.is_a? HashWithIndifferentAccess or args.is_a? Hash
      generic_search = GenericSearch::Klass.new(args, self.class)
      generic_search.search
    elsif args.is_a? GenericSearch

    else
      raise UnknownInputType
    end

  end

  def self.generic_search config
    GenericSearch.update_config(self.table_name, config[:custom_attributes])
  end

  def self._table_relation
    #@@table_relation ||= begin
    #  puts "processing..."
    self.reflect_on_all_associations.inject({}) do |hash, assoc_reflection|
      hash[assoc_reflection.table_name] ||= assoc_reflection.name
      hash
    end
    #end
  end

  def self._relation_table
    #@@relation_table ||= begin
    #puts "processing..."
    self.reflect_on_all_associations.inject({}) do |hash, assoc_reflection|
      hash[assoc_reflection.name] ||= assoc_reflection.table_name
      hash
    end
    #end
  end

end

#class ApplicationController
#
#  def _generic_search
#    base_class = self.class.to_s.gsub('Controller', '').singularize.constantize
#    generic_search = GenericSearch::Klass.new(params, base_class)
#    generic_search.search
#    response = generic_search.response
#
#    response[:client_IP] = self.request.headers["X-Cluster-Client-Ip"]
#    response[:controller] = controller_name.classify.to_s
#
#    render :json => generic_search.response
#  end
#
#  # Restrictions to the controller
#  # generic_search_config(false) # to disable the generic search in a controller
#  # generic_search_config(:model_class => Script) # to disable the generic search in a controller
#  def self.generic_search_config(restrictions)
#    # Restriction logic for controller
#  end
#
#end