class TopicsController < ApplicationController
  include ExtendedContentController

  def index
    redirect_to_search_for('Topic')
  end

  def list
    index
  end

  def show
    prepare_item_variables_for('Topic')
    @topic = @item

    respond_to do |format|
      format.html
      format.xml { render_oai_record_xml(:item => @topic) }
    end
  end

  def new
    @topic = Topic.new
    respond_to do |format|
      format.html
      format.js { render :file => File.join(RAILS_ROOT, 'app/views/topics/pick_form.js.rjs') }
    end
  end

  def edit
    @topic = Topic.find(params[:id])
    public_or_private_version_of(@topic)

    # logic to prevent plain old members from editing
    # site basket homepage
    if @topic != @site_basket.index_topic or permit? "site_admin of :site_basket or admin of :site_basket"
      @topic_types = @topic.topic_type.full_set
    else
      # this is the site's index page, but they don't have permission to edit
      flash[:notice] = 'You don\'t have permission to edit this topic.'
      redirect_to :action => 'show', :id => params[:id]
    end
  end

  def create
    begin

      # ultimately I would like url's for peole to do look like the following:
      # topics/people/mcginnis/john
      # topics/people/mcginnis/john_marshall
      # topics/people/mcginnis/john_robert
      # for places:
      # topics/places/nz/wellington/island_bay/the_parade/206
      # events:
      # topics/events/2006/10/31
      # in the meantime we'll just use :name or :first_names and :last_names

      # We need to set the topic_type first, because extended_content= depends on it.
      @topic = Topic.new(:topic_type_id => params[:topic][:topic_type_id])
      @topic.attributes = params[:topic]
      @successful = @topic.save


      # add this to the user's empire of creations
      # TODO: allow current_user whom is at least moderator to pick another user
      # as creator
      @topic.creator = current_user if @successful
    rescue
      flash[:error], @successful  = $!.to_s, false
    end

    where_to_redirect = 'show_self'
    if !params[:relate_to_topic].blank? and @successful
      @new_related_topic = Topic.find(params[:relate_to_topic])
      ContentItemRelation.new_relation_to_topic(@new_related_topic, @topic)

      # update the related topic
      # so this new relationship is reflected in search
      prepare_and_save_to_zoom(@new_related_topic)

      # make sure the related topics cache is cleared for related topic
      expire_related_caches_for(@new_related_topic, 'topics')

      where_to_redirect = 'show_related'
    end

    if params[:index_for_basket] and @successful
      where_to_redirect = 'basket'
    end

    if @successful
      build_relations_from_topic_type_extended_field_choices
      prepare_and_save_to_zoom(@topic)

      @topic.do_notifications_if_pending(1, current_user)

      case where_to_redirect
      when 'show_related'
        flash[:notice] = 'Related Topic was successfully created.'
        redirect_to_related_topic(@new_related_topic, { :private => (params[:related_topic_private] && params[:related_topic_private] == 'true' && permitted_to_view_private_items?) })
      when 'basket'
        redirect_to :action => 'add_index_topic',
        :controller => 'baskets',
        :index_for_basket => params[:index_for_basket],
        :topic => @topic
      else
        flash[:notice] = 'Topic was successfully created.'
        redirect_to :action => 'show', :id => @topic, :private => (params[:topic][:private] == "true")
      end
    else
      render :action => 'new'
    end
  end

  def update
    @topic = Topic.find(params[:id])
    public_or_private_version_of(@topic)

    # if they have changed the topic type, make the edit fail so they can review
    # the new fields (and to ensure that required fields are filled in). We have to
    # update the attribute so that when they save, the extended field validations
    # take effect. We also have to reload and then switch to the privacy of the item
    # they are editing (to ensure private item editing shows the correct data)
    if params[:topic][:topic_type_id] && @topic.topic_type_id != params[:topic][:topic_type_id].to_i
      # update the topic with the new topic type and version comment
      old_topic_type = TopicType.find(@topic.topic_type_id)
      new_topic_type = TopicType.find(params[:topic][:topic_type_id].to_i)
      @topic.update_attributes(
        :topic_type_id => params[:topic][:topic_type_id].to_i,
        :version_comment => "Changed Topic Type from #{old_topic_type.name} to #{new_topic_type.name}"
      )

      # add a contributor to the previous topic update
      version = @topic.versions.find(:first, :order => 'version DESC').version
      @topic.add_as_contributor(current_user, version)

      # reload, get the correct privacy and return the user to the topic form
      @topic.reload
      public_or_private_version_of(@topic)
      flash[:notice] = 'You\'ve changed the topic type for this topic. Please review the available fields.'
      @successful = false

    # logic to prevent plain old members from editing site basket homepage
    elsif @topic != @site_basket.index_topic || permit?("site_admin of :site_basket or admin of :site_basket")
      version_after_update = @topic.max_version + 1

      @successful = ensure_no_new_insecure_elements_in('topic')
      @topic.attributes = params[:topic]
      @successful = @topic.save if @successful
    else
      # they don't have permission
      # this will redirect them to edit
      # which will bump them back to show for the topic
      # with flash message
      @successful = false
    end

    if @successful
      after_successful_zoom_item_update(@topic, version_after_update)
      flash[:notice] = 'Topic was successfully updated.'
      redirect_to_show_for @topic, :private => (params[:topic][:private] == "true")
    else
      if @topic != @site_basket.index_topic or permit?("site_admin of :site_basket or admin of :site_basket")
        @topic_types = @topic.topic_type.full_set
      end
      render :action => 'edit'
    end
  end

  def destroy
    # delete relationship to any basket
    # basket's index page cache is already handled
    @topic = Topic.find(params[:id])
    index_for_basket = @topic.index_for_basket
    if !index_for_basket.nil?
      index_for_basket.update_index_topic('destroy')
    end

    zoom_destroy_and_redirect('Topic')
  end
end
