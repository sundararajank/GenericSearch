require 'active_record'
require 'generic_search/validation'
require 'generic_search/build_methods'
require 'generic_search/config'
require 'generic_search/exception'
require 'generic_search/rails_overrides'
require 'generic_search/validation'
require 'generic_search/messages'

module GenericSearch

  @@generic_search = {
      :config => {}
  }

  def self.update_config(class_name, config)
    @@generic_search[:config][class_name.intern] = config
  end

  def self.config
    @@generic_search[:config]
  end

  class Klass
    include ActiveModel::Validations
    include GenericSearch::Validation
    include GenericSearch::BuildMethods

    # Clause attributes
    attr_accessor :where, :includes, :joins, :select, :group, :having, :limit, :start, :sort_order, :options

    # Utility attributes
    attr_accessor :base_class, :base_table, :grouped_results, :params

    # Output attributes
    attr_accessor :status, :messages, :response, :results, :no_limit_count, :limit_result_count

    validate :validate_syntax

    # ===== To configure generic search in model =====
    #generic_search_config {
    #  table_alias: {
    #      transitions: transition
    #  }
    #}
    # ===== To configure generic search in model =====


    # ==== Hash Inputs: ===
    #{
    #    :query => "responsibles(username=ksmanoj)",
    #    :results => "scripts(id, name), responsibles",
    #    :limit => 5,
    #    :options => "no_results"
    #}
    def initialize(params, base_class)

      self.base_class = base_class.is_a?(String) ? base_class.constantize : base_class
      self.base_table = self.base_class.table_name

      unless params.is_a?(Hash) or params.is_a?(HashWithIndifferentAccess)
        raise GenericSearch::UnknownInputType
      end

      self.params = params

      self.validate_syntax

      return unless self.errors.blank?

      self.build_options(params[:options])
      self.build_where(params[:query])
      self.build_results(params[:results])
      self.build_group(params[:group])
      self.build_having(params[:having])
      self.build_limit(params[:limit])
      self.build_start(params[:start])
      self.build_sort_order(params[:sort_order])
    end

    def search

      unless self.errors.blank?
        self.status = :bad_request
        self.messages = self.errors.full_messages
        self.build_response
        return self.response
      end

      table_relation_map = self.base_class._table_relation
      relation_table_map = self.base_class._relation_table

      includes = Hash.new
      json_includes = Hash.new

      self.select.each do |table, value|
        table = table.strip
        relationship_name = table_relation_map[table]
        relationship_name = table.intern if !relationship_name or relation_table_map[table.intern]
        includes[relationship_name] = {} if table != self.base_table
        json_includes[relationship_name] = {:only => self.select[table]} if table != self.base_table
      end

      # TODO: Solve n+1 issue for custom columns
      #config = GenericSearch.config[self.base_table.intern][:for_select]
      #selected_fields = table_selected_fields[self.base_table]
      #
      #config.each do |custom_column, attrs|
      #  if attrs[:include] and selected_fields.include?(custom_column.to_s)
      #    selected_fields << attrs[:include]
      #  end
      #end

      self.results = self.base_class.where(self.where).joins(self.joins).includes(self.includes).reorder(self.sort_order)

      #result_list = @model_class.joins(@joins).includes(includes).where(@where_clause).distinct

      # TODO: Test required
      if self.options[:distinct]
        self.results = self.results.uniq
      end

      # ========== Limiting & Grouping =========
      # TODO: Test required
      if self.options[:no_grouped_results]
        if self.group
          self.results = self.results.group(self.group)
        end

        if self.having
          self.results = self.results.having(self.having)
        end
      else
        if self.group
          group_result_counts = self.results.group(self.group).count
        end
      end

      # TODO: If there is a limit then only following count query has to be executed otherwise use .length
      if self.options[:no_limit_count]
        # Note: If no limit or start, then .length will fire the query, from that length is calculated.
        # Additional count query is not required
        self.no_limit_count = (self.limit || self.start) ? self.results.count : self.results.length
        #self.no_limit_count = self.results.count
      end

      # TODO: Test required
      unless self.options[:no_results]
        self.results = self.results.limit(self.limit).offset(self.start)
      end

      # ============== Group result processing
      # TODO: Test required
      if group_result_counts
        # Hack to dynamically group the array of objects
        eval_str = @group_object_access.collect { |i| "result.#{i}.to_s" }.join(' + ')
        grouped_result = self.results.group_by { |result| eval eval_str }

        group_hsh = group_result_counts.collect do |values, group_result_count|

          values = values.is_a?(Array) ? values.collect(&:to_s) : [values.to_s]
          result_key = values.join('')

          results = if self.options[:no_results]
                      []
                    else
                      #grouped_result[result_key].as_json(:include => json_includes, :only => @table_selected_fields[self.base_table])
                      grouped_result[result_key].as_json(:include => json_includes, :only => self.select[self.base_table], :methods => self.select[self.base_table])
                    end

          {
              :group_by_field => self.group.join(', '),
              :group_by_value => values.join(','),
              :num_results => group_result_count,
              #:results => grouped_result[result_key]
              :results => results
          }
        end
      else
        results = if self.options[:no_results]
                    []
                  else

                    #self.results.as_json(:include => json_includes, :only => @table_selected_fields[self.base_table])
                    #self.results.as_json(:include => json_includes, :only => self.select[self.base_table], :methods => [:address_ids])
                    self.results.as_json(:include => json_includes, :only => self.select[self.base_table], :methods => self.select[self.base_table])
                  end

        group_hsh = [{:num_results => self.results.length, :results => results}]
      end

      self.grouped_results = group_hsh

      limit_result_count = 0

      self.grouped_results.each do |grouped_result|
        #limit_result_count += grouped_result["results"].count
        limit_result_count += grouped_result[:num_results]
      end

      self.limit_result_count = limit_result_count
      self.status = :ok
      self.build_response
    end

  end

end