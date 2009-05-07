module ActiveScaffold::Actions
  module Update
    def self.included(base)
      base.before_filter :update_authorized?, :only => [:edit, :update]
      base.verify :method => [:post, :put],
                  :only => :update,
                  :redirect_to => { :action => :index }
    end

    def edit
      do_edit

      respond_to do |type|
        type.html do
          if successful?
            render(:action => 'update')
          else
            return_to_main
          end
        end
        type.js do
          render(:partial => 'update_form')
        end
        edit_respond_to type if self.respond_to? :edit_respond_to
      end
    end

    def update
      do_update

      respond_to do |type|
        type.html do
          if params[:iframe]=='true' # was this an iframe post ?
            responds_to_parent do
              if successful?
                render :action => 'on_update.js'
              else
                render :action => 'form_messages_on_update.js'
              end
            end
          else # just a regular post
            if successful?
              if params[:wizard_controller]
                redirect_to_next_step
              else
                flash[:info] = as_(:updated_model, :model => @record.to_label)
                return_to_main
              end
            else
              render(:action => 'update')
            end
          end
        end
        type.js do
          render :action => 'on_update'
        end
        type.xml { render :xml => response_object.to_xml, :content_type => Mime::XML, :status => response_status }
        type.json { render :text => response_object.to_json, :content_type => Mime::JSON, :status => response_status }
        type.yaml { render :text => response_object.to_yaml, :content_type => Mime::YAML, :status => response_status }
        update_respond_to type if self.respond_to? :update_respond_to
      end
    end

    # for inline (inlist) editing
    def update_column
      do_update_column
      render :action => 'update_column'
    end

    protected

    # A simple method to find and prepare a record for editing
    # May be overridden to customize the record (set default values, etc.)
    def do_edit
      @record = find_if_allowed(params[:id], :update)
    end

    # A complex method to update a record. The complexity comes from the support for subforms, and saving associated records.
    # If you want to customize this algorithm, consider using the +before_update_save+ callback
    def do_update
      do_edit
      begin
        active_scaffold_config.model.transaction do
          @record = update_record_from_params(@record, active_scaffold_config.update.columns, params[:record])
          before_update_save(@record)
          self.successful = [@record.valid?, @record.associated_valid?].all? {|v| v == true} # this syntax avoids a short-circuit
          if successful?
            @record.save! and @record.save_associated!
            after_update_save(@record)
          end
        end
      rescue ActiveRecord::RecordInvalid
      rescue ActiveRecord::StaleObjectError
        @record.errors.add_to_base as_(:version_inconsistency)
        self.successful=false
      end
    end

    def do_update_column
      do_edit
      if @record.authorized_for?(:action => :update, :column => params[:column])
        params[:value] ||= @record.column_for_attribute(params[:column]).default unless @record.column_for_attribute(params[:column]).null
        @record.send("#{params[:column]}=", params[:value])
        @record.save
      end
    end

    # override this method if you want to inject data in the record (or its associated objects) before the save
    def before_update_save(record); end

    # override this method if you want to do something after the save
    def after_update_save(record); end

    # The default security delegates to ActiveRecordPermissions.
    # You may override the method to customize.
    def update_authorized?
      authorized_for?(:action => :update)
    end
  end
end