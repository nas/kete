class ExtendedFieldsController < ApplicationController

  helper ExtendedFieldsHelper

  # everything else is handled by application.rb
  before_filter :login_required, :only => [:list, :index, :add_field_to_multiples, :fetch_subchoices, :fetch_topics_from_topic_type ]

  before_filter :set_page_title

  permit "site_admin or admin of :site or tech_admin of :site",
          :except => [ :add_field_to_multiples, :fetch_subchoices, :fetch_topics_from_topic_type ]

  active_scaffold :extended_field do |config|
    # Default columns and column exclusions
    config.columns = [:label, :description, :xml_element_name, :ftype, :import_synonyms, :example, :multiple, :user_choice_addition]
    config.list.columns.exclude [:updated_at, :created_at, :topic_type_id, :xsi_type, :user_choice_addition]

    config.columns << [:base_url]
    config.columns[:base_url].label = "Base URL"
    config.columns[:base_url].description = "Whatever the user inputs will be appended to this base url (e.g. http://site.com/~[user_input]).</p><p>&nbsp;</p><p><b>NOTE:</b> in the case of any of the choice ftypes, Base URL + value will take over from normal linking to all results that match the value for the choice for the extended field. In the case of Location on map ftypes, supplying a base url will link the coordinates on display to the url, appending an ll (latitude/longitude) and z (zoom level) parametres (for ease of use with Google Maps - configurable in config/google_map_api.yml)"

    # CRUD for adding/removing choices
    config.columns << [:pseudo_choices]
    config.columns[:pseudo_choices].label = "Available choices"
    config.columns[:pseudo_choices].description = "Ftype must be a \"choices\" option for these options to be available to users."
    config.columns[:user_choice_addition].label = nil

    config.columns << [:topic_type]
    config.columns[:topic_type].label = "Topic Type Choices"
    config.columns[:topic_type].description = "Ftype must be a \"Pre-populated Choices (topic type)\" option for these options to be available to users."
  end

  def add_field_to_multiples

    extended_field = ExtendedField.find(params[:extended_field_id])
    n = params[:n].to_i
    @item_type_for_params = params[:item_key]

    render :update do |page|

      # Remove the field adder control
      page.remove "#{qualified_name_for_field(extended_field)}_multis_extender"

      # Add a new field editor to the bottom of the set
      page.insert_html :bottom, "#{qualified_name_for_field(extended_field)}_multis", \
        :partial => 'extended_fields/extended_field_editor', \
        :locals => { :ef => extended_field, :content => [], :n => n, :multiple => true }

      # Add the field adder control back to the bottom of the set
      page.insert_html :bottom, "#{qualified_name_for_field(extended_field)}_multis", \
        :partial => 'extended_fields/additional_extended_field_control', \
        :locals => { :ef => extended_field, :n => n.to_i + 1 }
    end
  end

  # Fetch subchoices for a choice.
  def fetch_subchoices

    extended_field = ExtendedField.find(params[:options][:extended_field_id])

    # Find the current choice
    current_choice = extended_field.choices.matching(params[:label], params[:value])

    blank_value = params[:label].blank? && params[:value].blank?

    choices = current_choice ? current_choice.children : []

    choices = choices.reject { |c| !extended_field.choices.member?(c) }

    options = {
      :choices => choices,
      :level => params[:for_level].to_i + 1,
      :extended_field => extended_field
    }

    # Ensure we have a standard environment to work with. Some parts of the helpers (esp. ID and NAME
    # attribute generation rely on these.
    @item_type_for_params = params[:item_type_for_params]
    @field_multiple_id = params[:field_multiple_id]


    render :update do |page|

      # Generate the DOM ID
      dom_id = "#{id_for_extended_field(options[:extended_field])}__level_#{params[:for_level]}"

      if blank_value || (options[:choices].blank? && !extended_field.user_choice_addition?)
        page.replace_html dom_id, ""
      else
        page.replace_html dom_id,
          :partial => "extended_fields/choice_#{params[:editor]}_editor",
          :locals => params[:options].merge(options)
      end
    end
  end

  def fetch_topics_from_topic_type
    begin
      extended_field = ExtendedField.find(params[:extended_field_id])
      parent_topic_type = extended_field.topic_type.to_i
      extended_field_key = @template.send(:id_for_extended_field, extended_field).gsub('_extended_content_values_', '').gsub(/_$/, '')
      logger.debug("What is extended_field_key: #{extended_field_key}")
      search_term = params[params[:extended_field_for]][:extended_content_values][extended_field_key]
      if extended_field.multiple?
        multiple_id = params[:multiple_id] || 1
        search_term = search_term[multiple_id]
      end
    rescue
      raise "Something went wrong getting the extended field, it's parent topic type or the users search term"
    end

    search_term = search_term.split(' (').first if search_term =~ /.+ \(.+\)/
    logger.debug("What is search term: #{search_term}")

    topic_type_ids = TopicType.find(parent_topic_type).full_set.collect { |a| a.id }

    topics = Topic.find(:all, :conditions => ["title LIKE ? AND topic_type_id IN (?)", "%#{search_term}%", topic_type_ids],
                        :order => "title ASC", :limit => 10)
    logger.debug("Topics are: #{topics.inspect}")

    topics = topics.map { |entry|
      @template.content_tag("li", "#{sanitize(entry.title)} (#{@template.url_for(:urlified_name => entry.basket.urlified_name,
                                                                          :controller => 'topics',
                                                                          :action => 'show',
                                                                          :id => entry,
                                                                          :only_path => false)})")
    }
    render :inline => @template.content_tag("ul", topics.uniq)
  end

  private

  def set_page_title
    @title = 'Extended Fields'
  end
end
