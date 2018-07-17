module GenericSearch

  module Validation

    def validate

    end

    def validate_syntax

      [params[:query], params[:results], params[:group]].each do |query_string|

        next if query_string.blank?

        #if query_string.include?(',,')
        if query_string.match(/\s*\,\s*\,\s*/)
          @status = :bad_request
          #@message = "malformed url - double comma"
          @message = GenericSearch::Messages::DoubleComma
          self.errors.add(:base, @message)
          #return false
        end

        #if query_string.include?('((')
        if query_string.match(/\s*\(\s*\(\s*/)
          @status = :bad_request
          @message = GenericSearch::Messages::DoubleOpenParan
          self.errors.add(:base, @message)
          #return false
        end

        # To check ))
        if query_string.match(/\s*\)\s*\)\s*/)
          @status = :bad_request
          @message = GenericSearch::Messages::DoubleCloseParan
          self.errors.add(:base, @message)
        end

        if query_string.count("()") % 2 == 1
          @status = :bad_request
          @message = GenericSearch::Messages::IncorrectUseOfParan
          self.errors.add(:base, @message)
        end
      end

      #if type.eql?("where_clause")
      #  puts "verifying specific legal query_strings for where_clause"
      #  if !query_string.include?('(')
      #    @status = :bad_request
      #    @message = "malformed url - no query arguments"
      #    return false
      #  end
      #end

      #return true
    end

    #def validate_table_columns
    #
    #  #self.validate_query
    #
    #end

    def validate_columns(table_name, column_names, clause)

      connection = ActiveRecord::Base.connection
      config = GenericSearch.config[table_name.intern]
      config_for_where = (config and config[:for_where]) || {}
      config_for_select = (config and config[:for_select]) || {}

      if !connection.table_exists?(table_name) and !self.base_class.reflections.has_key?(table_name)
        self.errors.add(:base, "'#{table_name}' table is invalid (in '#{clause}')")
        return
      end

      if !connection.table_exists?(table_name)
        if !self.base_class.reflections.has_key?(table_name)
          self.errors.add(:base, "'#{table_name}' table is invalid (in '#{clause}')")
          return
        else
          table_name = self.base_class._relation_table[table_name.intern]
        end
      end

      return if column_names.blank?

      unknown_columns = []

      column_names.each do |column_name|
        next if config_for_select and config_for_select.has_key?(column_name.intern)
        next if config_for_where and config_for_where.has_key?(column_name.intern)

        if !connection.column_exists?(table_name, column_name) and !config_for_select.has_key?(column_name.intern) and !config_for_where.has_key?(column_name.intern)
          unknown_columns << column_name
        end
      end

      if !unknown_columns.blank?
        self.errors.add(:base, "'#{unknown_columns.join(', ')}' column#{unknown_columns.size > 1 ? 's' : ''} not found in '#{table_name}' table (in '#{clause}')")
      end

    end

    def valid_syntax?(query_string)

    end

    def validate_query

    end

    def validate_results

    end

    def validate_group

    end

    def validate_sort_order

    end

    def validate_limit

    end

    #def validate_columns(table_name, column_names, clause)
    #
    #  connection = ActiveRecord::Base.connection
    #
    #  if !connection.table_exists?(table_name) and !self.base_class.reflections.has_key?(table_name.intern)
    #    @_uri_errors << "'#{table_name}' is invalid in '#{clause}'"
    #    return
    #  end
    #
    #  if !connection.table_exists?(table_name)
    #    if !self.base_class.reflections.has_key?(table_name.intern)
    #      @_uri_errors << "'#{table_name}' is invalid in '#{clause}'"
    #      return
    #    else
    #      table_name = self.base_class._relation_table[table_name.intern]
    #    end
    #  end
    #
    #  return if column_names.blank?
    #
    #  unknown_columns = []
    #
    #  config = GenericSearchMethods.config[table_name.intern]
    #  column_names.each do |column_name|
    #
    #    next if config and config.has_key?(column_name.intern)
    #
    #    if !connection.column_exists?(table_name, column_name)
    #      unknown_columns << column_name
    #    end
    #  end
    #
    #  if !unknown_columns.blank?
    #    @_uri_errors << "'#{unknown_columns.join(', ')}' column#{unknown_columns.size > 1 ? 's' : ''} not found in '#{table_name}' table in '#{clause}'"
    #  end
    #
    #end

    def validate_table_columns(table, columns)
      #connection = ActiveRecord::Base.connection

      #if connection.table_exists? table
      #
      #end

    end

    def validate_uri_syntax

    end

  end

end