module GenericSearch

  #def self.custom_config
  #  {
  #      :transitions => {
  #          :script_status => {
  #              :field => :script_status_id,
  #              :lambda => lambda do |operator, value|
  #                Status.where("name #{operator} ?", value).collect(&:id)
  #              end
  #          }
  #      }
  #  }
  #end

  module BuildMethods

    def build_where(query)

      if query.blank?
        return
      end

      query_table_list = []

      query.each_line('),') do |segment|
        segment.gsub!(/,$/, "")
        query_table_list << segment
      end

      query_per_table = Array.new

      @joins = []

      query_table_list.each do |query_item|

        table, search_params = query_item.to_s.split('(', 2)
        table.strip!

        column_names = []

        if table.strip != @base_table
          relation_name = @base_class._table_relation[table.strip]
          @joins << relation_name if relation_name
        end

        search_params ||= ''
        search_params.gsub!(/\)$/, "")

        single_param_array = search_params.strip.split(/\s*,\s*/)
        single_param_array_length = single_param_array.length

        column_values = []
        current_value = single_param_array[0]
        i=0

        until i >= single_param_array_length

          next_value = single_param_array[i + 1]

          if next_value.nil? or next_value.match(/([<>=!~]|between)/)
            column_values << current_value
            current_value = next_value
          else
            current_value << (',' + next_value)
          end

          i = i + 1
        end

        column_values.each do |search_param|
          search_param.gsub!(/,$/, "")

          if search_param.match(/(\w+)\s+between\s+(\*?.*)and(\*?.*)/i)
            key, from, to = $1.strip, $2.strip, $3.strip

            single_search_param = if from.match(/^\d+$/) and to.match(/^\d+$/)
                                    "\"#{table}\".\"#{key}\" between #{from} and #{to}"
                                  else
                                    "\"#{table}\".\"#{key}\" between '#{from.to_time.to_s(:db)}' and '#{to.to_time.to_s(:db)}'"
                                  end

          else
            search_param.match(/(\w+)(\s*[<>=!~]*\s*)(\*?.*)/)
            key, operator, value = $1.strip, $2.strip, $3.strip

            if operator == '='
              if value.include? '*'
                value.gsub!('*', '%')
                value = "#{value}"
                operator = self.options[:match_case].present?  ? 'LIKE':'ILIKE'
                operator = (value.match(/\%+|\*+/) and value.match(/\|+/))? "SIMILAR TO" : operator #match case will be considered here
                #elsif value.include? '/'
                #  value = "(#{value})"
                #  operator = 'in'
                #elsif value.include? '|'
                #  value = "(#{value})"
                #  operator = 'in'
                #else
                #  value = "'#{value}'"
              elsif value.include? '|'
                operator  = '='   # we can't add logic for match case here, so when user uses | then always "TT|BB|cc"  will be converted as name ="TT" OR "BB" OR "CC"
              else
                #Added for without match case for string  Run.tcl should match both Run.tcl or run.tcl if no match case option provided
                is_boolean = (value.present? and (value == true or value == "t" or value =='f' or value == "true" or value == "false" or value == false))
                is_number = (value.present? and value.match(/^\d+$/))
                is_multiple_number = (value.present? and value.match(/^\d+([\|\,\.]\d+)*$/)) # search with ids using | separated
                is_string = (value.present? and value.match(/^\S+$/))
                operator = ((self.options[:match_case].present? and is_string) or is_number or is_multiple_number or is_boolean)? operator : 'ILIKE'
              end
            else
              value = "#{value}"
            end

            config = GenericSearch.config[table.intern]
            config = (config and config[:for_where])
            key_intern = key.intern

            #TODO: Test Requires
            single_search_param = if config and config.has_key?(key_intern)
                                    config = config[key_intern]
                                    value = config[:lambda].call(operator, value)
                                    #subQuery = value.is_a?(Array) ? "in (#{value.blank? ? 'NULL' : value.join(',')})" : "= '#{value}'"
                                    subQuery = if value.is_a?(Array)
                                                 if value.blank?
                                                   "in (NULL)"
                                                 else
                                                   "in (#{value.join(',')})"
                                                 end
                                               else
                                                 "= '#{value}'"
                                               end
                                    "\"#{table}\".\"#{config[:field]}\" #{subQuery}"
                                  elsif operator == '=' and value.include?('|')

                                    value = value.gsub(/\s*\|\s*/, ' OR ').split(/(\sAND\s|\sOR\s)/)
                                    .collect do |val|
                                      val.match(/(\sAND\s|\sOR\s)/) ? val : "\"#{table}\".\"#{key}\" #{operator} '#{val.strip}'"
                                    end.join(' ')

                                    "(#{value})"

                                  elsif operator == '=' and value.include?(',')
                                    # AND Support should be handled in a different way
                                    # using group=user.id, having='ARRAY_AGG(users.id) @> ARRAY[23, 34, 45]::integer[]'
                                  else
                                    "\"#{table}\".\"#{key}\" #{operator} '#{value}'"
                                  end

            column_names << key
          end

          query_per_table << single_search_param if single_search_param
        end

        self.validate_columns(table, column_names, :query)
      end

      self.where = query_per_table.join(' AND ')
    end

    def build_results(results)
      table_selected_fields = {}

      selects = if results.blank?
                  [self.base_class.table_name]
                else
                  selects = results.scan(/\w+\(.*?\)/)
                  results_clone = results.clone

                  selects.each do |select|
                    results_clone.gsub!(select, '')
                  end

                  selects += results_clone.split(/,/).delete_if(&:blank?)
                  selects
                end

      selects.each do |select|
        match, table, select_fields = *select.match(/(\w+)\(*([\s\w,]*)\)*/)
        table_selected_fields[table] = select_fields.blank? ? nil : select_fields.strip.split(/\s*,\s*/)
      end

      table_selected_fields.each do |table_name, column_names|
        validate_columns(table_name, column_names, :results)
      end

      #TODO: self.select = table_selected_fields.clone
      self.select = table_selected_fields
    end

    def build_group(group)

      if group.blank?
        return
      end

      group_entities = group.scan(/\w+\(.*?\)/)

      @joins ||= []
      group_table_fields_map = {}
      @group = []
      @group_object_access = []

      group_entities.each do |group_entity|
        match, table, select_fields = *group_entity.match(/(\w+)\(*([\s\w,]*)\)*/)
        table.strip!
        fields = select_fields.split(/\s*,\s*/)
        group_table_fields_map[table] = fields

        #@joins << @base_class._table_relation[table.strip] if table != @base_class.table_name

        table.strip!
        if table != @base_table
          relation_name = (@base_class._table_relation[table] || (@base_class._relation_table[table.intern] ? table.intern : nil))
          table_name = @base_class._table_relation[table] ? table : @base_class._relation_table[table.intern]
          @joins << relation_name if relation_name
        else
          table_name = table
        end

        fields.each do |field|
          @group << "#{table_name}.#{field}"
          #@group_object_access << (@base_table == table ? field : "#{@base_class._table_relation[table]}.#{field}")
          @group_object_access << (@base_table == table_name ? field : "#{relation_name}.#{field}")
        end
      end

      group_table_fields_map.each do |table, column_names|
        validate_columns(table, column_names, :group)
      end


    end

    def build_having(having)
      if having.blank?
        return
      end

      self.having = having.gsub(/(^"|"$)/, '').strip
    end

    def build_sort_order(sort_order)
      self.sort_order = if sort_order.nil?
                          "\"#{self.base_table}\".\"id\" ASC"
                        elsif sort_order.strip == "\"\"" || sort_order.strip == "\'\'" || sort_order.strip == ''
                          nil
                        else
                          sort_order.strip
                        end
    end

    def build_limit(limit)
      #TODO: Test required for group.blank?
      if self.options[:no_results] or !self.group.blank?
        self.limit = nil
      else
        self.limit = limit.blank? ? GenericSearch::DEFAULT_LIMIT : limit
      end

    end

    def build_start(start)
      #TODO: Test required for group.blank?
      self.start = if self.options[:no_results] or !self.group.blank?
                     nil
                   else
                     start.blank? ? 0 : start
                   end
    end

    # options = no_results, no_limit_count
    def build_options(options)

      self.options = {}

      return if options.blank?

      if options.include? 'no_results'
        self.options[:no_results] = true
      end

      if options.include? 'no_limit_count'
        self.options[:no_limit_count] = true
      end

      if options.include? 'distinct'
        self.options[:distinct] = true
      end

      if options.include? 'no_grouped_results'
        self.options[:no_grouped_results] = true
      end
      if options.include? 'match_case'
        self.options[:match_case] = true
      end
    end

    def build_response

      self.response = {
          :success => self.status == :ok ? true : false,
          :code => self.status == :ok ? 200 : 400,
          :status => self.status,
          :message => self.messages,
          :client_IP => nil,
          :controller => nil,

          :server => Socket.gethostname,
          :where_clause => self.where,
          :no_limit_result_count => self.no_limit_count,
          :limit_result_count => self.limit_result_count,
          :timestamp => Time.now,
          :groups => self.grouped_results
          #"groups" => params.has_key?(:no_results) ? [] : @grouped_results
      }

    end

  end

end