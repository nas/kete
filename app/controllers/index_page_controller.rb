class IndexPageController < ApplicationController
  caches_page :robots

  # Kieran Pilkington, 2008/11/26
  # Instantiation of Google Map code for location settings
  include GoogleMap::Mapper

  def index
    if !@current_basket.index_page_redirect_to_all.blank?
      redirect_to_all_for(@current_basket.index_page_redirect_to_all)
    else
      @privacy_type = @current_basket.show_privacy_controls_with_inheritance? && permitted_to_view_private_items? ? 'private' : 'public'
      @allow_private = (@privacy_type == 'private')

      # Kieran Pilkington, 2008/08/06
      # Load the index page everytime (for now atleast, until a better title caching system is in place)
      @is_fully_cached = has_all_fragments?
      #if !@is_fully_cached or params[:format] == 'xml'
      @topic = @current_basket.index_topic(true) # must load this each time or the topic gets cached a private permanently next
      if @topic && (params[:private] == "true" || (params[:private].blank? && @current_basket.private_default_with_inheritance?)) &&
          @topic.has_private_version? && permitted_to_view_private_items?
          @topic = @topic.private_version!
      end

      if !@topic.nil?
        @title = @topic.title
      end

      if @current_basket != @site_basket or ( @topic.nil? and !@is_fully_cached )
        @title = @current_basket.name
      end

      if !@current_basket.index_topic.nil? && @current_basket.index_page_topic_is_entire_page
        render :action => :topic_as_full_page
      else
        if !@is_fully_cached

          if !has_fragment?({:part => 'details'}) and !@topic.nil?
            @comments = @topic.non_pending_comments
          end

          # TODO: DRY up
          @url_to_full_topic = nil
          @url_to_comments = nil
          if !@topic.nil?
            case @current_basket.index_page_link_to_index_topic_as
            when 'full topic and comments'
              @url_to_full_topic = url_for( :urlified_name => @topic.basket.urlified_name,
                                            :action => :show,
                                            :controller => 'topics',
                                            :id => @topic )
              @url_to_comments = url_for(:action => 'show',
                                         :urlified_name => @topic.basket.urlified_name,
                                         :controller => 'topics',
                                         :id => @topic,
                                         :anchor => 'comments')
            when 'full topic'
              @url_to_full_topic = url_for( :urlified_name => @topic.basket.urlified_name,
                                            :action => :show,
                                            :controller => 'topics',
                                            :id => @topic )
            when 'comments'
              @url_to_comments = url_for(:action => 'show',
                                         :urlified_name => @topic.basket.urlified_name,
                                         :controller => 'topics',
                                         :id => @topic,
                                         :anchor => 'comments')
            end
          end

          # prepare blog list of most recent topics
          # replace limit with param from basket
          @recent_topics_limit = @current_basket.index_page_number_of_recent_topics
          @recent_topics_limit = 0 if @recent_topics_limit.blank?

          if @recent_topics_limit > 0
            # get an array of baskets that we need to exclude from the site recent topics list
            disabled_recent_topics_baskets = Array.new
            if @current_basket == @site_basket
              disabled_recent_topics_baskets = ConfigurableSetting.find_all_by_name_and_value('disable_site_recent_topics_display', true.to_yaml, :select => :configurable_id, :conditions => ["configurable_id != ?", @site_basket])
              disabled_recent_topics_baskets.collect! { |setting| setting.configurable_id }
            end
            # If we have a blank array, reset it to nil so later on, it'll default to 0 (instead of causing the SQL to return nothing)
            disabled_recent_topics_baskets = nil unless disabled_recent_topics_baskets.size > 0

            # form our find arguments
            args = { :offset => 0, :limit => @recent_topics_limit, :include => :versions }
            args[:conditions] = ["basket_id NOT IN (?) AND id != ?", (disabled_recent_topics_baskets || 0), (@topic || 0)]

            @recent_topics_items = Array.new
            @total_items = Topic.count

            # We need to loop over all topics until we have a complete array. If for example the
            # first 5 topics have all versions disputed, then we end up with nothing being displayed
            # on the homepage. By using a while, we can resolve this issue
            while @recent_topics_items.size < @recent_topics_limit && args[:offset] <= @total_items
              # Make the find query based on current basket and privacy level
              if @current_basket == @site_basket
                recent_topics_items = @allow_private ? Topic.recent(args) : Topic.recent(args).public
              else
                recent_topics_items = @allow_private ? @current_basket.topics.recent(args) : @current_basket.topics.recent(args).public
              end

              # Cycle through the 5 recent topics, and get the latest unflagged
              # version with the privacy that the current user is able to see
              recent_topics_items.collect! do |topic|
                if @allow_private && topic.latest_version_is_private?
                  topic.latest_unflagged_version_with_condition { |v| v.private? }
                else
                  topic.latest_unflagged_version_with_condition { |v| !v.private? }
                end
              end

              logger.debug("recent_topics_items after reverse recursive selection: " + recent_topics_items.inspect)

              # If the version we have isn't available, remove it
              recent_topics_items.reject! { |topic| topic.disputed_or_not_available? }

              logger.debug("recent_topics_items after rejection: " + recent_topics_items.inspect)

              # Add to the recent_topics_items array the amount we need to complete it
              unless recent_topics_items.blank?
                amount_left = (@recent_topics_limit - @recent_topics_items.size)
                @recent_topics_items << recent_topics_items[0..(amount_left - 1)]

                # We end up with [[<Topic>, <Topic>], [<Topic>], [<Topic>]] at this point,
                # lets make it [<Topic>, <Topic>, <Topic>, <Topic>] for the next loop
                @recent_topics_items = @recent_topics_items.flatten.compact
              end

              # incase we don't have enough yet, loop over the next set
              # increase the offset by @recent_topics_limit amount
              args[:offset] += @recent_topics_limit
            end

            # with the final topic, sort by the versions created_at,
            # rather than the public topics created_at
            @recent_topics_items.sort! { |t1,t2| t2.created_at<=>t1.created_at }
          end
        end

        # don't bother caching selected image or tags list,
        # because both are likely to change constantly, and
        # neither of them rely on the homepage topic
        selected_image

        if @current_basket.index_page_number_of_tags && @current_basket.index_page_number_of_tags > 0
          @tag_counts_array = @current_basket.tag_counts_array(:allow_private => @allow_private)
          @tag_counts_total = @current_basket.tag_counts_total(:allow_private => @allow_private)
        end
      end
    end
  end

  def selected_image
    # get next url from slideshow, if slideshow exists,
    # or this url is the last url in results
    # otherwise, create a new slide show based on basket settings

    # reformat into a standard_url, for results comparison in slideshow
    url_hash = { :controller => 'index_page', :action => 'selected_image' }
    @current_url = url_for(url_hash.merge(:id => params[:id]))

    # hash keys have to be strings
    # so as not to trip up later comparisons
    slideshow_key = { "basket" => @current_basket.id,
      "order" => @current_basket.index_page_image_as,
      "zoom_class" => 'StillImage' }

    if !session[:slideshow].blank? && slideshow.key == slideshow_key && !slideshow.in_set?(@current_url) && !slideshow.last_requested.blank?
      @current_url = slideshow.after(slideshow.last_requested)
    end

    id_string = @current_url.split("/").last
    if id_string =~ /([0-9]+)/
      @current_id = $1
    else
      @current_id = nil
    end

    @selected_still_image = nil

    if !session[:slideshow].blank? && slideshow.in_set?(@current_url) && slideshow.key == slideshow_key
      @selected_still_image = still_image_from_slideshow
    else
      # put together results
      # normally results are paged
      # and when you hit the last result in a page
      # the next page of results is built or something like that
      # and they are derived by hitting search controller

      limit = 20

      find_args_hash = { :select => 'id, title, created_at', :limit => limit }

      # We have to make sure the image is public on the site basket, or if they dont have permission to view it
      # there is no way to get all private from the site basket and public from others without another query
      unless @privacy_type == 'private'
        find_args_hash.merge!(:conditions => ["(#{PUBLIC_CONDITIONS}) AND (file_private = :file_private OR file_private is null)",
                                              { :file_private => false }])
      end

      # we need public still images
      case @current_basket.index_page_image_as
      when 'random'
        find_args_hash[:order] = :random
      when 'latest'
        find_args_hash[:order] = 'created_at desc'
      end

      if @current_basket != @site_basket
        @still_image_ids = @current_basket.still_images.find(:all, find_args_hash)
      else
        @still_image_ids = StillImage.find(:all, find_args_hash)
      end

      session[:slideshow] = nil
      if !@still_image_ids.blank?
        total_images = @still_image_ids.size
        slideshow.key = slideshow_key
        slideshow.results = @still_image_ids.collect { |id| url_for(url_hash.merge(:id => id)) }
        slideshow.total = total_images
        slideshow.total_pages = 1
        slideshow.current_page = 1
        slideshow.number_per_page = total_images
        @current_id = @still_image_ids.first
        @selected_still_image = StillImage.find(@current_id)
        @current_url = url_for(url_hash.merge(:id => @current_id))
      end
    end

    @selected_image_file = ImageFile.find_by_thumbnail_and_still_image_id('medium', @selected_still_image ) if !@selected_still_image.nil?

    if !session[:slideshow].blank? && !slideshow.results.nil?
      @previous_url = slideshow.in_set?(@current_url) ? slideshow.before(@current_url) : nil
      @next_url = slideshow.in_set?(@current_url) ? slideshow.after(@current_url) : nil

      # keep track of where we are in the results
      slideshow.last_requested = !slideshow.last?(@current_url) ? @current_url : nil
    else
      @previous_url = nil
      @next_url = nil
    end

    # get still image and image_file
    if request.xhr?
      render :partial =>'selected_image',
      :locals => { :selected_image_file => @selected_image_file,
        :previous_url => @previous_url,
        :next_url => @next_url,
        :selected_still_image => @selected_still_image }
    else
      if params[:action] == 'selected_image'
        redirect_to params.merge(:action => 'index')
      end
    end
  end

  def still_image_from_slideshow
    still_image = nil
    id = @current_id || params[:id]
    if @current_basket != @site_basket
      still_image = @current_basket.still_images.find(id)
    else
      still_image = StillImage.find(id)
    end
    still_image
  end

  def topic_as_full_page
  end

  def help_file
    # Walter McGinnis, 2008-02-18
    # bug fix only
    # this needs to take a parameter for which help page
    # in the future
    # fairly brittle now
    @topic = @help_basket.topics.find_by_title("Adding things")
    @title = @topic.title
    @creator = @topic.creator
    @last_contributor = @topic.contributors.last || @creator
    @comments = @topic.comments

    render :action => :topic_as_full_page, :layout => "simple"
  end

  def uptime
    render(:text => "success")
  end

  # run a query to make sure the db is available
  # comments are usually the smallest set of items
  def db_uptime
    comment_count = Comment.count
    render(:text => "success")
  end

  # let's check to make sure zebra is responding
  # this will only return success if you can connect
  # to both the public and private databases
  # private commented out until privacy control functionality is merged in
  def zebra_uptime
    zoom_dbs = [ZoomDb.find_by_database_name('public')]
    # zoom_dbs <<  ZoomDb.find_by_database_name('private')
    zoom_dbs.each { |db| Module.class_eval('Topic').process_query(:zoom_db => db, :query => "@attr 1=_ALLRECORDS @attr 2=103 ''")}
    render(:text => "success")
  end

  def validate_kete_net_link
    render(:xml => { :url => SITE_URL, :datetime => "#{Time.new.utc.xmlschema}" })
  end

  # page that tells search engines where not to go
  # search forms, rss feeds, user comments etc
  def robots
    @baskets = Basket.all
    @controller_names = ZOOM_CLASSES.collect { |name| zoom_class_controller(name) }
    render :action => 'robots', :layout => false
  end

end
