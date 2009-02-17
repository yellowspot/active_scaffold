module ActiveScaffold
  module Helpers
    # Helpers that assist with the rendering of a List Column
    module ListColumnHelpers
      include ActionView::Helpers::JavaScriptMacrosHelper
      
      def get_column_value(record, column)
        begin
          # check for an override helper
          value = if column_override? column
            # we only pass the record as the argument. we previously also passed the formatted_value,
            # but mike perham pointed out that prohibited the usage of overrides to improve on the
            # performance of our default formatting. see issue #138.
            send(column_override(column), record, column)
          # second, check if the dev has specified a valid list_ui for this column
          elsif column.list_ui and override_column_ui?(column.list_ui)
            send(override_column_ui(column.list_ui), column, record)

          elsif column.inplace_edit and record.authorized_for?(:action => :update, :column => column.name)
            active_scaffold_inplace_edit(record, column)
          elsif override_column_ui?(column.column.type)
            send(override_column_ui(column.column.type), column, record)
          else
            value = record.send(column.name)

            if column.association.nil? or column_empty?(value)
              formatted_value = clean_column_value(format_value(value))
            else
              case column.association.macro
                when :has_one, :belongs_to
                  formatted_value = clean_column_value(format_value(value.to_label))

                when :has_many, :has_and_belongs_to_many
				          if column.associated_limit.nil?
                    firsts = value.collect { |v| v.to_label }
                  else
                    firsts = value.first(column.associated_limit + 1).collect { |v| v.to_label }
                    firsts[column.associated_limit] = '…' if firsts.length > column.associated_limit
				          end
                  formatted_value = clean_column_value(format_value(firsts.join(', ')))
                  formatted_value << " (#{value.length})" if column.associated_number? and column.associated_limit and firsts.length > column.associated_limit
                  formatted_value
              end
            end

            formatted_value
          end

          value = '&nbsp;' if value.nil? or (value.respond_to?(:empty?) and value.empty?) # fix for IE 6
          return value
        rescue Exception => e
          logger.error Time.now.to_s + "#{e.inspect} -- on the ActiveScaffold column = :#{column.name} in #{@controller.class}"
          raise e
        end
      end

      # TODO: move empty_field_text and &nbsp; logic in here?
      # TODO: move active_scaffold_inplace_edit in here?
      # TODO: we need to distinguish between the automatic links *we* create and the ones that the dev specified. some logic may not apply if the dev specified the link.
      def render_list_column(text, column, record)
        make_available_method = "#{column.name}_make_available?"
        return active_scaffold_config.list.empty_field_text if record.respond_to?(make_available_method) and !record.send(make_available_method)
        if column.link
          link = column.link.clone
          if column.singular_association? and column_empty?(text) 
            if column.options[:show_create_link_if_empty].blank?
              return "<a class='disabled'>#{text}</a>"
            else
              column_model = column.association.klass
              controller_actions = active_scaffold_config_for(column_model).actions
              if controller_actions.include?(:create) and column.actions_for_association_links.include? :new and column_model.authorized_for?(:action => :create)
                link.action = 'new'
                link.crud_type = :create
                text = as_(:create_new)
              end
            end
          end
          return "<a class='disabled'>#{text}</a>" unless record.authorized_for?(:action => column.link.crud_type)

          url_options = params_for(:action => nil, :id => record.id, :link => text)
          if column.singular_association? and column.link.action != 'nested'
            if associated = record.send(column.association.name)
              url_options[:id] = associated.id
            elsif link.action == 'new'
              url_options.delete :id
              url_options[:parent_id] = record.id
              url_options[:parent_column] = column.association.reverse
              constraints = {url_options[:parent_column].to_sym => url_options[:parent_id]}
              eid = Digest::MD5.hexdigest(params[:controller] + params[:parent_controller].to_s + constraints.to_s)
              session["as:#{eid}"] = {:constraints => constraints}
              url_options[:eid] = eid
            end
          end

          render_action_link(link, url_options)
        else
          text
        end
      end

      # There are two basic ways to clean a column's value: h() and sanitize(). The latter is useful
      # when the column contains *valid* html data, and you want to just disable any scripting. People
      # can always use field overrides to clean data one way or the other, but having this override
      # lets people decide which way it should happen by default.
      #
      # Why is it not a configuration option? Because it seems like a somewhat rare request. But it
      # could eventually be an option in config.list (and config.show, I guess).
      def clean_column_value(v)
        h(v)
      end

      ##
      ## Overrides
      ##
      def active_scaffold_column_text(column, record)
        truncate(clean_column_value(record.send(column.name)), :length => 50)
      end

      def active_scaffold_column_checkbox(column, record)
        column_value = record.send(column.name)
        checked = column_value.class.to_s.include?('Class') ? column_value : column_value == 1
        if column.inplace_edit and record.authorized_for?(:action => :update, :column => column.name)
          id_options = {:id => record.id.to_s, :action => 'update_column', :name => column.name.to_s}
          tag_options = {:tag => "span", :id => element_cell_id(id_options), :class => "in_place_editor_field"}
          script = remote_function(:method => 'POST', :url => {:controller => params_for[:controller], :action => "update_column", :column => column.name, :id => record.id.to_s, :value => !column_value, :eid => params[:eid]})
          content_tag(:span, check_box_tag(tag_options[:id], 1, checked, {:onchange => script}) , tag_options)
        else
          check_box_tag(nil, 1, checked, :disabled => true)
        end
      end

      def column_override(column)
        "#{column.name.to_s.gsub('?', '')}_column" # parse out any question marks (see issue 227)
      end

      def column_override?(column)
        respond_to?(column_override(column))
      end

      def override_column_ui?(list_ui)
        respond_to?(override_column_ui(list_ui))
      end

      # the naming convention for overriding column types with helpers
      def override_column_ui(list_ui)
        "active_scaffold_column_#{list_ui}"
      end

      ##
      ## Formatting
      ##

      def format_value(column_value)
        if column_empty?(column_value)
          active_scaffold_config.list.empty_field_text
        elsif column_value.instance_of? Time
          format_time(column_value)
        elsif column_value.instance_of? Date
          format_date(column_value)
        else
          column_value.to_s
        end
      end

      def format_time(time)
        format = ActiveSupport::CoreExtensions::Time::Conversions::DATE_FORMATS[:default] || "%m/%d/%Y %I:%M %p"
        time.strftime(format)
      end

      def format_date(date)
        format = ActiveSupport::CoreExtensions::Date::Conversions::DATE_FORMATS[:default] || "%m/%d/%Y"
        date.strftime(format)
      end

      # =======
      # = AST =
      # =======
      def nested_label(association)
        as_(:nested_for_model, :nested_model => active_scaffold_config_for(association.klass).label, :parent_model => format_value(@record.to_label))
      end
      
      def list_action_authorized?(link, record)
       !(controller.respond_to?(link.security_method) and ((controller.method(link.security_method).arity == 0 and !controller.send(link.security_method)) or (controller.method(link.security_method).arity == 1 and !controller.send(link.security_method, link)))) and record.authorized_for?(:action => link.crud_type)
      end
      
      def active_scaffold_column_percentage(column, record)
        number_to_percentage(record[column.name].to_s, :precision => 1)
      end

      def active_scaffold_column_ssn(column, record)
        usa_number_to_ssn(record[column.name].to_s)
      end

      def active_scaffold_column_usa_money(column, record)
        number_to_currency(record[column.name].to_s)
      end

      def active_scaffold_column_usa_phone(column, record)
        usa_number_to_phone(record[column.name].to_s)
      end

      def active_scaffold_column_usa_zip(column, record)
        usa_number_to_zip(record[column.name].to_s)
      end
    end
  end
end